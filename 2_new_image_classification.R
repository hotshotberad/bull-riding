# Load required packages
library(shiny) # builds interactive web apps
library(bslib) # provides styling and visual themes for Shiny apps
library(magick) # handles image processing
library(fs) # manages file and directory operations

# File path setup
base_dir   <- "/Users/bradley/Desktop/coding/projects/bull"
image_dir  <- file.path(base_dir, "review_images")
## Folders where training images and labels will be stored.
train_img  <- file.path(base_dir, "dataset", "images", "train")
train_label  <- file.path(base_dir, "dataset", "labels", "train")

# Ensure destination folders exist on disk before the app begins
dir_create(c(train_img, train_label))

# User interface (UI)
## Defines what the user sees and interacts with on the screen.
ui <- page_sidebar(
    theme = bs_theme(bootswatch = "flatly"),
    title = "R Bull Riding Image Review & Labeler",
    ## Left-hand control panel
    sidebar = sidebar(
        ## Dropdown to select what you are labeling (Cowboy vs. Bull)
        selectInput("class_select", "Active Class:",
                    choices = c("Cowboy (0)" = 0, "Bull (1)" = 1)),
        hr(),
        ## Action buttons for approving, navigating, and resetting boxes
        actionButton("approve_img", "✔ Approve & Save to Train", class = "btn-success w-100 mb-2"),
        actionButton("prev_img", "◀ Previous Image", class = "btn-secondary w-100 mb-2"),
        actionButton("next_img", "Next Image ▶", class = "btn-primary w-100 mb-2"),
        ## Undo button: Removes only the most recently drawn box
        actionButton("undo_box", "↩ Undo Last Box", class = "btn-info w-100 mb-2"),
        actionButton("clear_boxes", "Clear Annotations", class = "btn-warning w-100 mb-2"),
        hr(),
        ## Text block showing current progress and image details
        verbatimTextOutput("status_text")
    ),

    ## Main display area showing the current image and bounding boxes
    card(
        card_header("Verify predictions, adjust boxes if needed, then click Approve"),
        plotOutput("image_plot",
                   ## Enables click-and-drag drawing directly on top of the image
                   brush = brushOpts(id = "plot_brush", resetOnNew = TRUE),
                   height = "600px")
    )
)

# Server logic
## Handles backend operations (data storage, drawing, file operations)
server <- function(input, output, session) {
    ## Reactive variables: dynamic memory slots that update and refresh the UI automatically
    image_files   <- reactiveVal(character(0)) ## Holds the list of image file paths waiting for review
    current_idx   <- reactiveVal(1)            ## Tracks the index of the image currently being viewed
    current_boxes <- reactiveVal(data.frame(   ## Stores active bounding box coordinates for the current image
        class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()
    ))

    ## Helper function: Scans the review folder to see what images remain
    refresh_files <- function() {
        files <- list.files(image_dir, pattern = "\\.(jpg|jpeg|png)$", full.names = TRUE, ignore.case = TRUE)
        image_files(files)
        if (length(files) == 0) {
            current_idx(0)
        } else if (current_idx() > length(files)) {
            current_idx(length(files))
        }
    }

    ## Perform the initial directory scan when the app launches
    observe({
        refresh_files()
    })

    ## Helper function: Reads existing YOLO-format text labels and translates them into pixel boxes
    ## (YOLO stores boxes as percentages of width/height centered at x, y; we convert them to exact pixel corners)
    load_annotations <- function(img_path, img_w, img_h) {
        txt_path <- sub("\\.[^.]+$", ".txt", img_path)
        if (!file.exists(txt_path)) return(data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()))

        lines <- readLines(txt_path, warn = FALSE)
        lines <- lines[nchar(trimws(lines)) > 0]
        if (length(lines) == 0) return(data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()))

        parsed <- do.call(rbind, lapply(strsplit(lines, " "), as.numeric))
        cls <- parsed[, 1]
        xc  <- parsed[, 2] * img_w
        yc  <- parsed[, 3] * img_h
        w   <- parsed[, 4] * img_w
        h   <- parsed[, 5] * img_h

        data.frame(
            class = as.integer(cls),
            xmin = xc - (w / 2),
            ymin = yc - (h / 2),
            xmax = xc + (w / 2),
            ymax = yc + (h / 2)
        )
    }

    ## Helper function: Converts pixel coordinates back into normalized (0 to 1) YOLO text format and saves to disk
    save_annotations <- function(img_path, boxes, img_w, img_h) {
        txt_path <- sub("\\.[^.]+$", ".txt", img_path)
        if (nrow(boxes) == 0) {
            if (file.exists(txt_path)) file.remove(txt_path)
            return()
        }

        xc <- ((boxes$xmin + boxes$xmax) / 2) / img_w
        yc <- ((boxes$ymin + boxes$ymax) / 2) / img_h
        w  <- (boxes$xmax - boxes$xmin) / img_w
        h  <- (boxes$ymax - boxes$ymin) / img_h

        yolo_lines <- sprintf("%d %.6f %.6f %.6f %.6f", boxes$class, xc, yc, w, h)
        writeLines(yolo_lines, txt_path)
    }

    ## Whenever the active image changes, read its dimensions and load existing box labels
    observe({
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0, idx <= length(files))

        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        loaded_boxes <- load_annotations(img_path, info$width, info$height)
        current_boxes(loaded_boxes)
    })

    ## When the user clicks and drags a box on the image, add the new bounding box and auto-save it
    observeEvent(input$plot_brush, {
        brush <- input$plot_brush
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        new_box <- data.frame(
            class = as.integer(input$class_select),
            xmin  = brush$xmin,
            ymin  = brush$ymin,
            xmax  = brush$xmax,
            ymax  = brush$ymax
        )

        updated <- rbind(current_boxes(), new_box)
        current_boxes(updated)

        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, updated, info$width, info$height)
    })

    ## Approve button: Moves reviewed image and label files to the permanent training folder
    observeEvent(input$approve_img, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        img_path <- files[idx]
        txt_path <- sub("\\.[^.]+$", ".txt", img_path)

        ## Move the image file to the training directory
        file_move(img_path, file.path(train_img, path_file(img_path)))

        ## Move matching text label file if one exists
        if (file.exists(txt_path)) {
            file_move(txt_path, file.path(train_label, path_file(txt_path)))
        }

        ## Refresh the remaining queue
        refresh_files()
    })

    ## Navigation: Move forward one image
    observeEvent(input$next_img, {
        if (current_idx() < length(image_files())) {
            current_idx(current_idx() + 1)
        }
    })

    ## Navigation: Move back one image
    observeEvent(input$prev_img, {
        if (current_idx() > 1) {
            current_idx(current_idx() - 1)
        }
    })

    ## Undo: Remove only the last bounding box drawn on the image
    observeEvent(input$undo_box, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        boxes <- current_boxes()
        if (nrow(boxes) > 0) {
            ## Drop the last row from the boxes table
            updated <- boxes[-nrow(boxes), , drop = FALSE]
            current_boxes(updated)

            img_path <- files[idx]
            info <- image_info(image_read(img_path))
            save_annotations(img_path, updated, info$width, info$height)
        }
    })

    ## Reset: Remove all bounding boxes on the current image
    observeEvent(input$clear_boxes, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)
        current_boxes(data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()))
        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, current_boxes(), info$width, info$height)
    })

    ## Render the main interactive canvas (drawing the image and its labeled boxes)
    output$image_plot <- renderPlot({
        files <- image_files()
        idx <- current_idx()

        ## Display an empty placeholder if no images are left to review
        if (length(files) == 0 || idx == 0) {
            plot(0, 0, type = "n", axes = FALSE, xlab = "", ylab = "")
            text(0, 0, "No more images to review!", cex = 1.5, col = "gray40")
            return()
        }

        ## Load the image and configure a borderless canvas matching its dimensions
        img_path <- files[idx]
        img <- image_read(img_path)
        info <- image_info(img)

        par(mar = c(0, 0, 0, 0))
        plot(0, 0, type = "n", xlim = c(0, info$width), ylim = c(info$height, 0),
             xaxs = "i", yaxs = "i", axes = FALSE, xlab = "", ylab = "")

        raster_img <- as.raster(img)
        rasterImage(raster_img, 0, info$height, info$width, 0)

        ## Draw all existing bounding boxes and color-coded labels (Blue = Cowboy, Red = Bull)
        boxes <- current_boxes()
        if (nrow(boxes) > 0) {
            for (i in seq_len(nrow(boxes))) {
                b <- boxes[i, ]
                col <- ifelse(b$class == 0, "dodgerblue", "firebrick")
                label <- ifelse(b$class == 0, "Cowboy", "Bull")

                ## Draw outer box border
                rect(b$xmin, b$ymin, b$xmax, b$ymax, border = col, lwd = 3)
                ## Draw label background tag
                rect(b$xmin, b$ymin - 20, b$xmin + (nchar(label) * 12) + 10, b$ymin, col = col, border = NA)
                ## Draw label text inside tag
                text(b$xmin + 5, b$ymin - 7, labels = label, col = "white", font = 2, adj = c(0, 0.5), cex = 1.1)
            }
        }
    })

    ## Render sidebar text showing how many images remain and active box counts
    output$status_text <- renderText({
        files <- image_files()
        if (length(files) == 0) return("Queue empty: All images approved!")
        sprintf("Review Queue: %d remaining\nFile: %s\nBoxes: %d",
                length(files), basename(files[current_idx()]), nrow(current_boxes()))
    })
}

# Launch the Shiny application
shinyApp(ui, server)
