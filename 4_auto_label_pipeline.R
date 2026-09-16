library(reticulate)
library(av)
library(fs)

use_virtualenv("r-yolo-env", required = TRUE)
ultralytics <- import("ultralytics")

base_dir   <- "/Users/bradley/Desktop/coding/projects/bull"
review_dir <- file.path(base_dir, "review_images")

# 1. Clear out any unapproved leftovers from the previous run
if (dir_exists(review_dir)) {
    dir_delete(review_dir)
}
dir_create(review_dir)

# 2. Sample frames from the trimmed extraction
frames_dir <- file.path(base_dir, "images")
# Sort files chronologically by filename/creation order
extracted  <- sort(list.files(frames_dir, pattern = "\\.jpg$", full.names = TRUE))

if (length(extracted) == 0) {
    stop("No extracted frames found in ", frames_dir, ". Did Script 1 run correctly?")
}

# Select up to 20 evenly spaced frames across the entire ride duration
n_sample <- min(20, length(extracted))
indices  <- round(seq(1, length(extracted), length.out = n_sample))
sampled_imgs <- extracted[indices]

# Copy selected frames to review directory
file_copy(sampled_imgs, review_dir, overwrite = TRUE)

# 2. Run model predictions on the sampled images
# Point to your best checkpoint from training
model_path <- file.path(base_dir, "runs", "detect", "train", "weights", "best.pt")
model <- ultralytics$YOLO(model_path)

# Predict on review directory and write .txt annotations alongside images
results <- model$predict(
    source   = review_dir,
    conf     = 0.25,
    save_txt = FALSE # We will write the .txt directly into review_dir below
)

# 3. Save predicted boxes as .txt in the exact format expected by your Shiny app
for (r in results) {
    orig_path <- r$path
    txt_path  <- sub("\\.[^.]+$", ".txt", orig_path)
    boxes     <- r$boxes

    if (length(boxes) > 0) {
        # xywhn returns normalized: x_center, y_center, width, height
        xywhn <- boxes$xywhn$cpu()$numpy()
        classes <- as.integer(boxes$cls$cpu()$numpy())

        lines <- sprintf("%d %.6f %.6f %.6f %.6f", classes, xywhn[, 1], xywhn[, 2], xywhn[, 3], xywhn[, 4])
        writeLines(lines, txt_path)
    }
}
message("Inference complete. Frames ready for review in: ", review_dir)





