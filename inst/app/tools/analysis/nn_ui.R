nn_plots <- c("None" = "", "Network" = "net", "Olden" = "olden", "Garson" = "garson")

## list of function arguments
nn_args <- as.list(formals(nn))

## list of function inputs selected by user
nn_inputs <- reactive({
  ## loop needed because reactive values don't allow single bracket indexing
  nn_args$data_filter <- if (input$show_filter) input$data_filter else ""
  nn_args$dataset <- input$dataset
  for (i in r_drop(names(nn_args)))
    nn_args[[i]] <- input[[paste0("nn_", i)]]
  nn_args
})

nn_pred_args <- as.list(if (exists("predict.nn")) {
  formals(predict.nn)
} else {
  formals(radiant.model:::predict.nn)
})

# list of function inputs selected by user
nn_pred_inputs <- reactive({
  # loop needed because reactive values don't allow single bracket indexing
  for (i in names(nn_pred_args))
    nn_pred_args[[i]] <- input[[paste0("nn_", i)]]

  nn_pred_args$pred_cmd <- nn_pred_args$pred_data <- ""
  if (input$nn_predict == "cmd") {
    nn_pred_args$pred_cmd <- gsub("\\s", "", input$nn_pred_cmd) %>% gsub("\"", "\'", .)
  } else if (input$nn_predict == "data") {
    nn_pred_args$pred_data <- input$nn_pred_data
  } else if (input$nn_predict == "datacmd") {
    nn_pred_args$pred_cmd <- gsub("\\s", "", input$nn_pred_cmd) %>% gsub("\"", "\'", .)
    nn_pred_args$pred_data <- input$nn_pred_data
  }
  nn_pred_args
})

nn_pred_plot_args <- as.list(if (exists("plot.model.predict")) {
  formals(plot.model.predict)
} else {
  formals(radiant.model:::plot.model.predict)
} )

# list of function inputs selected by user
nn_pred_plot_inputs <- reactive({
  # loop needed because reactive values don't allow single bracket indexing
  for (i in names(nn_pred_plot_args))
    nn_pred_plot_args[[i]] <- input[[paste0("nn_", i)]]
  nn_pred_plot_args
})

output$ui_nn_rvar <- renderUI({
  req(input$nn_type)

  withProgress(message = "Acquiring variable information", value = 1, {
    if (input$nn_type == "classification") {
      vars <- two_level_vars()
    } else {
      vars <- varnames()[.getclass() %in% c("numeric", "integer")]
    }
  })

  # init <- ifelse(input$nn_type == "classification", input$logit_rvar, input$reg_rvar)

  init <- if (input$nn_type == "classification") {
    input$logit_rvar
  } else {
    input$reg_rvar
  }

  selectInput(
    inputId = "nn_rvar",
    label = "Response variable:",
    choices = vars,
    selected = state_single("nn_rvar", vars, init),
    multiple = FALSE
  )
})

output$ui_nn_lev <- renderUI({
  req(input$nn_type == "classification")
  req(available(input$nn_rvar))
  levs <- .getdata()[[input$nn_rvar]] %>%
    as_factor() %>%
    levels()

  selectInput(
    inputId = "nn_lev", label = "Choose level:",
    choices = levs,
    selected = state_init("nn_lev")
  )
})

output$ui_nn_evar <- renderUI({
  if (not_available(input$nn_rvar)) return()
  vars <- varnames()
  if (length(vars) > 0) {
    vars <- vars[-which(vars == input$nn_rvar)]
  }

  init <- if (input$nn_type == "classification") {
    input$logit_evar
  } else {
    input$reg_evar
  }

  selectInput(
    inputId = "nn_evar",
    label = "Explanatory variables:",
    choices = vars,
    selected = state_multiple("nn_evar", vars, init),
    multiple = TRUE,
    size = min(10, length(vars)),
    selectize = FALSE
  )
})

output$ui_nn_wts <- renderUI({
  vars <- varnames()[.getclass() %in% c("numeric", "integer")]
  if (length(vars) > 0 && any(vars %in% input$nn_evar)) {
    vars <- setdiff(vars, input$nn_evar)
    names(vars) <- varnames() %>%
      {.[match(vars, .)]} %>%
      names()
  }
  vars <- c("None", vars)

  selectInput(
    inputId = "nn_wts", label = "Weights:", choices = vars,
    selected = state_single("nn_wts", vars),
    multiple = FALSE
  )
})

output$ui_nn_store_pred_name <- renderUI({
  init <- state_init("nn_store_pred_name", "predict_nn") %>%
    sub("\\d{1,}$", "", .) %>%
    paste0(., ifelse(is_empty(input$nn_size), "", input$nn_size))

  textInput(
    "nn_store_pred_name",
    "Store predictions:",
    init
  )
})

output$ui_nn_store_res_name <- renderUI({
  init <- state_init("nn_store_res_name", "residuals_nn") %>%
    sub("\\d{1,}$", "", .) %>%
    paste0(., ifelse(is_empty(input$nn_size), "", input$nn_size))

  textInput(
    "nn_store_res_name",
    "Store residuals:",
    init
  )
})

## reset prediction settings when the dataset changes
observeEvent(input$dataset, {
  updateSelectInput(session = session, inputId = "nn_predict", selected = "none")
})

output$ui_nn_predict_plot <- renderUI({
  predict_plot_controls("nn")
})

output$ui_nn <- renderUI({
  req(input$dataset)
  tagList(
    wellPanel(
      actionButton("nn_run", "Estimate model", width = "100%", icon = icon("play"), class = "btn-success")
    ),
    conditionalPanel(
      condition = "input.tabs_nn == 'Predict'",
      wellPanel(
        selectInput(
          "nn_predict", label = "Prediction input:", reg_predict,
          selected = state_single("nn_predict", reg_predict, "none")
        ),
        conditionalPanel(
          "input.nn_predict == 'data' | input.nn_predict == 'datacmd'",
          selectizeInput(
            inputId = "nn_pred_data", label = "Predict for profiles:",
            choices = c("None" = "", r_data$datasetlist),
            selected = state_single("nn_pred_data", c("None" = "", r_data$datasetlist)), multiple = FALSE
          )
        ),
        conditionalPanel(
          "input.nn_predict == 'cmd' | input.nn_predict == 'datacmd'",
          returnTextAreaInput(
            "nn_pred_cmd", "Prediction command:",
            value = state_init("nn_pred_cmd", ""),
            rows = 3,
            placeholder = "Type a formula to set values for model variables (e.g., carat = 1; cut = 'Ideal') and press return"
          )
        ),
        conditionalPanel(
          condition = "input.nn_predict != 'none'",
          checkboxInput("nn_pred_plot", "Plot predictions", state_init("nn_pred_plot", FALSE)),
          conditionalPanel(
            "input.nn_pred_plot == true",
            uiOutput("ui_nn_predict_plot")
          )
        ),
        ## only show if full data is used for prediction
        conditionalPanel(
          "input.nn_predict == 'data' | input.nn_predict == 'datacmd'",
          tags$table(
            # tags$td(textInput("nn_store_pred_name", "Store predictions:", state_init("nn_store_pred_name", "predict_nn"))),
            tags$td(uiOutput("ui_nn_store_pred_name")),
            tags$td(actionButton("nn_store_pred", "Store"), style = "padding-top:30px;")
          )
        )
      )
    ),
    conditionalPanel(
      condition = "input.tabs_nn == 'Plot'",
      wellPanel(
        selectInput(
          "nn_plots", "Plots:", choices = nn_plots,
          selected = state_single("nn_plots", nn_plots)
        )
      )
    ),
    wellPanel(
      radioButtons(
        "nn_type", label = NULL, c("classification", "regression"),
        selected = state_init("nn_type", "classification"),
        inline = TRUE
      ),
      uiOutput("ui_nn_rvar"),
      uiOutput("ui_nn_lev"),
      uiOutput("ui_nn_evar"),
      uiOutput("ui_nn_wts"),
      tags$table(
        tags$td(numericInput(
          "nn_size", label = "Size:", min = 1, max = 20,
          value = state_init("nn_size", 1), width = "77px"
        )),
        tags$td(numericInput(
          "nn_decay", label = "Decay:", min = 0, max = 1,
          step = .1, value = state_init("nn_decay", .5), width = "77px"
        )),
        tags$td(numericInput(
          "nn_seed", label = "Seed:",
          value = state_init("nn_seed", 1234), width = "77px"
        ))
      ),
      conditionalPanel(
        condition = "input.tabs_nn == 'Summary'",
        tags$table(
          # tags$td(textInput("nn_store_res_name", "Store residuals:", state_init("nn_store_res_name", "residuals_nn"))),
          tags$td(uiOutput("ui_nn_store_res_name")),
          tags$td(actionButton("nn_store_res", "Store"), style = "padding-top:30px;")
        )
      )
    ),
    help_and_report(
      modal_title = "Neural Network",
      fun_name = "nn",
      help_file = inclMD(file.path(getOption("radiant.path.model"), "app/tools/help/nn.md"))
    )
  )
})

nn_plot <- reactive({
  if (nn_available() != "available") return()
  req(input$nn_plots)
  res <- .nn()
  if (is.character(res)) return()
  mlt <- if ("net" %in% input$nn_plots) 45 else 30
  plot_height <- max(500, length(res$model$coefnames) * mlt)
  list(plot_width = 650, plot_height = plot_height)
})

nn_plot_width <- function()
  nn_plot() %>% {
    if (is.list(.)) .$plot_width else 650
  }

nn_plot_height <- function()
  nn_plot() %>% {
    if (is.list(.)) .$plot_height else 500
  }

nn_pred_plot_height <- function()
  if (input$nn_pred_plot) 500 else 0


## output is called from the main radiant ui.R
output$nn <- renderUI({
  register_print_output("summary_nn", ".summary_nn")
  register_plot_output(
    "plot_nn_net", ".plot_nn_net",
    height_fun = "nn_plot_height",
    width_fun = "nn_plot_width"
  )
  register_print_output("predict_nn", ".predict_print_nn")
  register_plot_output(
    "predict_plot_nn", ".predict_plot_nn",
    height_fun = "nn_pred_plot_height"
  )
  register_plot_output(
    "plot_nn", ".plot_nn",
    height_fun = "nn_plot_height",
    width_fun = "nn_plot_width"
  )

  ## three separate tabs
  nn_output_panels <- tabsetPanel(
    id = "tabs_nn",
    tabPanel(
      "Summary",
      verbatimTextOutput("summary_nn")
    ),
    tabPanel(
      "Predict",
      conditionalPanel(
        "input.nn_pred_plot == true",
        plot_downloader("nn", height = nn_pred_plot_height, po = "dlp_", pre = ".predict_plot_"),
        plotOutput("predict_plot_nn", width = "100%", height = "100%")
      ),
      downloadLink("dl_nn_pred", "", class = "fa fa-download alignright"), br(),
      verbatimTextOutput("predict_nn")
    ),
    tabPanel(
      "Plot", plot_downloader("nn", height = nn_plot_height),
      plotOutput("plot_nn", width = "100%", height = "100%")
    )
  )

  stat_tab_panel(
    menu = "Model > Estimate",
    tool = "Neural Network",
    tool_ui = "ui_nn",
    output_panels = nn_output_panels
  )
})

nn_available <- reactive({
  if (not_available(input$nn_rvar)) {
    return("This analysis requires a response variable with two levels and one\nor more explanatory variables. If these variables are not available\nplease select another dataset.\n\n" %>% suggest_data("titanic"))
  }

  if (not_available(input$nn_evar)) {
    return("Please select one or more explanatory variables.\n\n" %>% suggest_data("titanic"))
  }

  "available"
})

.nn <- eventReactive(input$nn_run, {
  withProgress(
    message = "Estimating model", value = 1,
    do.call(nn, nn_inputs())
  )
})

.summary_nn <- reactive({
  if (nn_available() != "available") return(nn_available())
  if (not_pressed(input$nn_run)) return("** Press the Estimate button to estimate the model **")

  summary(.nn())
})

.predict_nn <- reactive({
  if (nn_available() != "available") return(nn_available())
  if (not_pressed(input$nn_run)) return("** Press the Estimate button to estimate the model **")
  if (is_empty(input$nn_predict, "none")) return("** Select prediction input **")

  if ((input$nn_predict == "data" || input$nn_predict == "datacmd") && is_empty(input$nn_pred_data)) {
    return("** Select data for prediction **")
  }
  if (input$nn_predict == "cmd" && is_empty(input$nn_pred_cmd)) {
    return("** Enter prediction commands **")
  }

  withProgress(message = "Generating predictions", value = 1, {
    do.call(predict, c(list(object = .nn()), nn_pred_inputs()))
  })
})

.predict_print_nn <- reactive({
  .predict_nn() %>% {
    if (is.character(.)) cat(., "\n") else print(.)
  }
})

.predict_plot_nn <- reactive({
  if (nn_available() != "available") return(nn_available())
  req(input$nn_pred_plot, available(input$nn_xvar))
  if (not_pressed(input$nn_run)) return(invisible())
  if (is_empty(input$nn_predict, "none")) return(invisible())
  if ((input$nn_predict == "data" || input$nn_predict == "datacmd") && is_empty(input$nn_pred_data)) {
    return(invisible())
  }
  if (input$nn_predict == "cmd" && is_empty(input$nn_pred_cmd)) {
    return(invisible())
  }

  do.call(plot, c(list(x = .predict_nn()), nn_pred_plot_inputs()))
})

.plot_nn <- reactive({
  if (nn_available() != "available") {
    return(nn_available())
  }

  req(input$nn_size)

  if (is_empty(input$nn_plots)) {
    return("Please select a neural network plot from the drop-down menu")
  }
  if (not_pressed(input$nn_run)) {
    return("** Press the Estimate button to estimate the model **")
  }

  pinp <- list(plots = input$nn_plots, shiny = TRUE)

  if (input$nn_plots == "net") {
    .nn() %>% {
      if (is.character(.)) invisible() else capture_plot(do.call(plot, c(list(x = .), pinp)))
    }
  } else {
    do.call(plot, c(list(x = .nn()), pinp))
  }
})

observeEvent(input$nn_store_pred, {
  req(!is_empty(input$nn_pred_data), pressed(input$nn_run))
  pred <- .predict_nn()
  if (is.null(pred)) return()
  withProgress(
    message = "Storing predictions", value = 1,
    store(pred, data = input$nn_pred_data, name = input$nn_store_pred_name)
  )
})

observeEvent(input$nn_store_res, {
  req(pressed(input$nn_run))
  robj <- .nn()
  if (!is.list(robj)) return()
  withProgress(
    message = "Storing residuals", value = 1,
    store(robj, name = input$nn_store_res_name)
  )
})

output$dl_nn_pred <- downloadHandler(
  filename = function() {
    "nn_predictions.csv"
  },
  content = function(file) {
    if (pressed(input$nn_run)) {
      .predict_nn() %>% write.csv(file = file, row.names = FALSE)
    } else {
      cat("No output available. Press the Estimate button to generate results", file = file)
    }
  }
)

observeEvent(input$nn_report, {
  if (is_empty(input$nn_evar)) return(invisible())

  outputs <- c("summary")
  inp_out <- list(list(prn = TRUE), "")
  xcmd <- ""
  figs <- FALSE

  if (!is_empty(input$nn_plots)) {
    inp_out[[2]] <- list(plots = input$nn_plots, custom = FALSE)
    outputs <- c(outputs, "plot")
    figs <- TRUE
  }

  if (!is_empty(input$nn_predict, "none") &&
    (!is_empty(input$nn_pred_data) || !is_empty(input$nn_pred_cmd))) {
    pred_args <- clean_args(nn_pred_inputs(), nn_pred_args[-1])
    inp_out[[2 + figs]] <- pred_args

    outputs <- c(outputs, "pred <- predict")

    xcmd <- paste0(xcmd, "\nprint(pred, n = 10)")
    if (input$nn_predict %in% c("data", "datacmd")) {
      xcmd <- paste0(xcmd, "\nstore(pred, data = \"", input$nn_pred_data, "\", name = \"", input$nn_store_pred_name, "\")")
    }

    if (getOption("radiant.local", default = FALSE)) {
      pdir <- getOption("radiant.write_dir", default = "~/")
      xcmd <- paste0(xcmd, "\n# readr::write_csv(pred, path = \"", pdir, "nn", input$nn_size, "_predictions.csv\")")
    }

    if (input$nn_pred_plot && !is_empty(input$nn_xvar)) {
      inp_out[[3 + figs]] <- clean_args(nn_pred_plot_inputs(), nn_pred_plot_args[-1])
      inp_out[[3 + figs]]$result <- "pred"
      outputs <- c(outputs, "plot")
      figs <- TRUE
    }
  }

  nn_inp <- nn_inputs()
  if (input$nn_type == "regression") {
    nn_inp$lev <- NULL
  }

  update_report(
    inp_main = clean_args(nn_inp, nn_args),
    fun_name = "nn",
    inp_out = inp_out,
    outputs = outputs,
    figs = figs,
    fig.width = nn_plot_width(),
    fig.height = nn_plot_height(),
    xcmd = xcmd
  )
})