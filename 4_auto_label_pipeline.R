# Load required packages
library(reticulate)
library(av)
library(fs)

# Establish virtual environment and import python's ultralytics
use_virtualenv("r-yolo-env", required = TRUE)
ultralytics <- import("ultralytics")

# Set paths to project folder and image review folder
base_dir   <- "/Users/bradley/Desktop/coding/projects/bull"
review_dir <- file.path(base_dir, "review_images")

# 1. Clear out any leftovers from the previous run
if (dir_exists(review_dir)) {
    dir_delete(review_dir)
}
dir_create(review_dir)

# 2. Sample frames from the trimmed extraction
frames_dir <- file.path(base_dir, "images")

## Sort files chronologically by filename/creation order
extracted  <- sort(list.files(frames_dir, pattern = "\\.jpg$", full.names = TRUE))

if (length(extracted) == 0) {
    stop("No extracted frames found in ", frames_dir, ". Did Script 1 run correctly?")
}

## Select up to 20 evenly spaced frames across the entire ride duration
n_sample <- min(20, length(extracted))
indices  <- round(seq(1, length(extracted), length.out = n_sample))
sampled_imgs <- extracted[indices]

# Copy selected frames to review directory
file_copy(sampled_imgs, review_dir, overwrite = TRUE)

# 2. Run model predictions on the sampled images
## Point to your best checkpoint from training
model_path <- file.path(base_dir, "runs", "detect", "train", "weights", "best.pt")
model <- ultralytics$YOLO(model_path)

## Predict on review directory and write .txt annotations alongside images
results <- model$predict(
    source   = review_dir,
    conf     = 0.25,
    save_txt = FALSE # Will write the .txt directly into review_dir below
)

# 3. Save at most 1 Cowboy (class 0) and 1 Bull (class 1) per image
for (r in results) {
    orig_path <- r$path
    txt_path  <- sub("\\.[^.]+$", ".txt", orig_path)
    boxes     <- r$boxes

    if (length(boxes) > 0) {
        # Extract coordinates, classes, and confidence scores
        xywhn   <- boxes$xywhn$cpu()$numpy()
        classes <- as.integer(boxes$cls$cpu()$numpy())
        confs   <- as.numeric(boxes$conf$cpu()$numpy())

        # Collect detections into a data frame for easy filtering
        det_df <- data.frame(
            class = classes,
            conf  = confs,
            xc    = xywhn[, 1],
            yc    = xywhn[, 2],
            w     = xywhn[, 3],
            h     = xywhn[, 4]
        )

        # Filter: Keep at most the highest-confidence detection for each class
        # (Only classes 0 and 1)
        selected_rows <- list()
        for (target_cls in c(0L, 1L)) {
            cls_subset <- det_df[det_df$class == target_cls, , drop = FALSE]
            if (nrow(cls_subset) > 0) {
                # Pick the detection with the highest confidence score
                best_row <- cls_subset[which.max(cls_subset$conf), ]
                selected_rows[[length(selected_rows) + 1]] <- best_row
            }
        }

        # If any boxes qualified (0, 1, or 2 total), write them out
        if (length(selected_rows) > 0) {
            filtered_df <- do.call(rbind, selected_rows)
            lines <- sprintf("%d %.6f %.6f %.6f %.6f",
                             filtered_df$class,
                             filtered_df$xc,
                             filtered_df$yc,
                             filtered_df$w,
                             filtered_df$h)
            writeLines(lines, txt_path)
        } else {
            # If no cowboy or bull passed confidence, remove any stale text file
            if (file.exists(txt_path)) file.remove(txt_path)
        }
    } else {
        if (file.exists(txt_path)) file.remove(txt_path)
    }
}

message("Inference complete. Frames ready for review in: ", review_dir)
