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

# 2. Extract frames from the new video
video_path      <- file.path(base_dir, "raw_video", "ride_raw.mp4")
temp_frames_dir <- file.path(base_dir, "temp_frames")

if (dir_exists(temp_frames_dir)) {
    dir_delete(temp_frames_dir)
}
dir_create(temp_frames_dir)

# Extract frames (e.g., 2 fps)
extracted <- av::av_video_images(video = video_path, destdir = temp_frames_dir, format = "jpg", fps = 2)

# Pick N random frames to review
set.seed(Sys.time())
n_sample     <- min(20, length(extracted))
sampled_imgs <- sample(extracted, n_sample)

# Copy sampled frames to review directory and remove temp folder
file_copy(sampled_imgs, review_dir, overwrite = TRUE)
dir_delete(temp_frames_dir)

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
