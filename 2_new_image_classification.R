# Load required packages
library(shiny)   # builds interactive web apps
library(bslib)   # provides styling and visual themes for Shiny apps
library(magick)  # handles image processing
library(fs)      # manages file operations

# File path setup
base_dir    <- "/Users/bradley/Desktop/coding/projects/bull"
image_dir   <- file.path(base_dir, "review_images")
train_img   <- file.path(base_dir, "dataset", "images", "train")
train_label <- file.path(base_dir, "dataset", "labels", "train")

# Ensure destination folders exist on disk before the app begins
dir_create(c(train_img, train_label))

# User Interface (UI)
ui <- page_sidebar(
    theme = bs_theme(bootswatch = "flatly"),
    title = "R Bull Riding Image Review & Labeler",
    sidebar = sidebar(
        selectInput("class_select", "Active Class:",
                    choices = c("Cowboy (0)" = 0, "Bull (1)" = 1)),
        hr(),
        h5("Box-by-Box Review"),
        div(class = "d-flex gap-1 mb-2",
            actionButton("prev_box", "◀ Prev Box", class = "btn-secondary btn-sm flex-fill"),
            actionButton("next_box", "Next Box ▶", class = "btn-secondary btn-sm flex-fill")
        ),
        actionButton("change_box_class", "Set Active Box to Selected Class", class = "btn-info w-100 mb-2"),
        actionButton("delete_active_box", "✖ Delete Active Box", class = "btn-danger w-100 mb-2"),
        actionButton("undo_box", "↩ Undo Last Drawn Box", class = "btn-outline-secondary w-100 mb-2"),
        actionButton("clear_boxes", "Clear All Annotations", class = "btn-warning w-100 mb-2"),
        hr(),
        h5("Image Review"),
        actionButton("approve_img", "✔ Approve & Save to Train", class = "btn-success w-100 mb-2"),
        actionButton("prev_img", "◀ Previous Image", class = "btn-secondary w-100 mb-2"),
        actionButton("next_img", "Next Image ▶", class = "btn-primary w-100 mb-2"),
        hr(),
        verbatimTextOutput("status_text")
    ),

    card(
        card_header("Click a box or use Prev/Next Box to inspect candidates. Draw by dragging. Click Approve when satisfied."),
        plotOutput("image_plot",
                   click = "plot_click",
                   brush = brushOpts(id = "plot_brush", resetOnNew = TRUE),
                   height = "600px")
    )
)

# Server Logic
server <- function(input, output, session) {
    image_files      <- reactiveVal(character(0))
    current_idx      <- reactiveVal(1)
    selected_box_idx <- reactiveVal(0)
    current_boxes    <- reactiveVal(data.frame(
        class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()
    ))

    # Scan review folder to see what images remain
    refresh_files <- function() {
        files <- list.files(image_dir, pattern = "\\.(jpg|jpeg|png)$", full.names = TRUE, ignore.case = TRUE)
        image_files(files)
        if (length(files) == 0) {
            current_idx(0)
            selected_box_idx(0)
        } else if (current_idx() > length(files)) {
            current_idx(length(files))
        }
    }

    # Perform initial directory scan on launch
    observe({
        refresh_files()
    })

    # Read YOLO text annotations into pixel coordinates
    load_annotations <- function(img_path, img_w, img_h) {
        txt_path <- sub("\\.[^.]+$", ".txt", img_path)
        if (!file.exists(txt_path)) {
            return(data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()))
        }

        lines <- readLines(txt_path, warn = FALSE)
        lines <- lines[nchar(trimws(lines)) > 0]
        if (length(lines) == 0) {
            return(data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric()))
        }

        parsed <- do.call(rbind, lapply(strsplit(lines, " "), as.numeric))
        cls <- parsed[, 1]
        xc  <- parsed[, 2] * img_w
        yc  <- parsed[, 3] * img_h
        w   <- parsed[, 4] * img_w
        h   <- parsed[, 5] * img_h

        data.frame(
            class = as.integer(cls),
            xmin  = xc - (w / 2),
            ymin  = yc - (h / 2),
            xmax  = xc + (w / 2),
            ymax  = yc + (h / 2)
        )
    }

    # Save pixel coordinates back into normalized YOLO text format
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

    # Load annotations when active image index changes
    observe({
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0, idx <= length(files))

        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        loaded_boxes <- load_annotations(img_path, info$width, info$height)
        current_boxes(loaded_boxes)
        selected_box_idx(if (nrow(loaded_boxes) > 0) 1 else 0)
    })

    # Select box by clicking directly inside it on the plot
    observeEvent(input$plot_click, {
        clk <- input$plot_click
        boxes <- current_boxes()
        if (nrow(boxes) == 0) return()

        hits <- which(clk$x >= boxes$xmin & clk$x <= boxes$xmax &
                          clk$y >= boxes$ymin & clk$y <= boxes$ymax)

        if (length(hits) > 0) {
            selected_box_idx(hits[length(hits)])
        }
    })

    # Navigate forward through boxes
    observeEvent(input$next_box, {
        boxes <- current_boxes()
        if (nrow(boxes) > 0) {
            new_idx <- min(nrow(boxes), selected_box_idx() + 1)
            selected_box_idx(new_idx)
        }
    })

    # Navigate backward through boxes
    observeEvent(input$prev_box, {
        boxes <- current_boxes()
        if (nrow(boxes) > 0) {
            new_idx <- max(1, selected_box_idx() - 1)
            selected_box_idx(new_idx)
        }
    })

    # Reclassify the selected box to the class chosen in the dropdown
    observeEvent(input$change_box_class, {
        idx <- selected_box_idx()
        boxes <- current_boxes()
        req(nrow(boxes) > 0, idx >= 1, idx <= nrow(boxes))

        boxes[idx, "class"] <- as.integer(input$class_select)
        current_boxes(boxes)

        img_path <- image_files()[current_idx()]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, boxes, info$width, info$height)
    })

    # Delete only the currently active box
    observeEvent(input$delete_active_box, {
        idx <- selected_box_idx()
        boxes <- current_boxes()
        req(nrow(boxes) > 0, idx >= 1, idx <= nrow(boxes))

        updated <- boxes[-idx, , drop = FALSE]
        current_boxes(updated)

        if (nrow(updated) == 0) {
            selected_box_idx(0)
        } else {
            selected_box_idx(min(idx, nrow(updated)))
        }

        img_path <- image_files()[current_idx()]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, updated, info$width, info$height)
    })

    # Add a new box by dragging with the mouse brush
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
        selected_box_idx(nrow(updated))

        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, updated, info$width, info$height)
    })

    # Undo the last drawn box
    observeEvent(input$undo_box, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        boxes <- current_boxes()
        if (nrow(boxes) > 0) {
            updated <- boxes[-nrow(boxes), , drop = FALSE]
            current_boxes(updated)
            selected_box_idx(if (nrow(updated) == 0) 0 else min(selected_box_idx(), nrow(updated)))

            img_path <- files[idx]
            info <- image_info(image_read(img_path))
            save_annotations(img_path, updated, info$width, info$height)
        }
    })

    # Clear all bounding boxes on the current image
    observeEvent(input$clear_boxes, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        empty_df <- data.frame(class = integer(), xmin = numeric(), ymin = numeric(), xmax = numeric(), ymax = numeric())
        current_boxes(empty_df)
        selected_box_idx(0)

        img_path <- files[idx]
        info <- image_info(image_read(img_path))
        save_annotations(img_path, empty_df, info$width, info$height)
    })

    # Approve and move files into training dataset
    observeEvent(input$approve_img, {
        files <- image_files()
        idx <- current_idx()
        req(length(files) > 0, idx > 0)

        img_path <- files[idx]
        txt_path <- sub("\\.[^.]+$", ".txt", img_path)

        file_move(img_path, file.path(train_img, path_file(img_path)))
        if (file.exists(txt_path)) {
            file_move(txt_path, file.path(train_label, path_file(txt_path)))
        }

        refresh_files()
    })

    # Image navigation
    observeEvent(input$next_img, {
        if (current_idx() < length(image_files())) {
            current_idx(current_idx() + 1)
        }
    })

    observeEvent(input$prev_img, {
        if (current_idx() > 1) {
            current_idx(current_idx() - 1)
        }
    })

    # Render image canvas with highlighted active box
    output$image_plot <- renderPlot({
        files <- image_files()
        idx <- current_idx()

        if (length(files) == 0 || idx == 0) {
            plot(0, 0, type = "n", axes = FALSE, xlab = "", ylab = "")
            text(0, 0, "No more images to review!", cex = 1.5, col = "gray40")
            return()
        }

        img_path <- files[idx]
        img <- image_read(img_path)
        info <- image_info(img)

        par(mar = c(0, 0, 0, 0))
        plot(0, 0, type = "n", xlim = c(0, info$width), ylim = c(info$height, 0),
             xaxs = "i", yaxs = "i", axes = FALSE, xlab = "", ylab = "")

        raster_img <- as.raster(img)
        rasterImage(raster_img, 0, info$height, info$width, 0)

        boxes <- current_boxes()
        sel_idx <- selected_box_idx()

        if (nrow(boxes) > 0) {
            for (i in seq_len(nrow(boxes))) {
                b <- boxes[i, ]
                is_active <- (i == sel_idx)

                class_name <- ifelse(b$class == 0, "Cowboy", "Bull")
                default_col <- ifelse(b$class == 0, "dodgerblue", "firebrick")

                # The active box is rendered with a prominent gold highlight
                border_col <- if (is_active) "#FFD700" else default_col
                border_lwd <- if (is_active) 5 else 2
                border_lty <- if (is_active) "solid" else "dashed"

                rect(b$xmin, b$ymin, b$xmax, b$ymax, border = border_col, lwd = border_lwd, lty = border_lty)

                # Text label tag above box
                tag_label <- paste0("#", i, " ", class_name)
                tag_w <- (nchar(tag_label) * 11) + 12
                rect(b$xmin, b$ymin - 22, b$xmin + tag_w, b$ymin, col = border_col, border = NA)
                text(b$xmin + 5, b$ymin - 9, labels = tag_label,
                     col = if (is_active) "black" else "white",
                     font = 2, adj = c(0, 0.5), cex = 1.05)
            }
        }
    })

    # Status panel displaying queue progress and active box information
    output$status_text <- renderText({
        files <- image_files()
        if (length(files) == 0) return("Queue empty: All images approved!")
        boxes <- current_boxes()
        total_boxes <- nrow(boxes)
        cur_box <- selected_box_idx()

        sprintf("Images Remaining: %d\nFile: %s\nTotal Boxes: %d\nActive Box: %s",
                length(files),
                basename(files[current_idx()]),
                total_boxes,
                if (total_boxes == 0) "None" else sprintf("%d of %d", cur_box, total_boxes))
    })
}

# Launch the Shiny application
shinyApp(ui, server)
