library(reticulate)

# 1. Create a dedicated virtual environment for your computer vision project
virtualenv_create("r-yolo-env")

# 2. Install ultralytics into this specific virtual environment
virtualenv_install("r-yolo-env", packages = c("ultralytics", "torch", "torchvision"))

# 3. Explicitly tell reticulate to use this environment
use_virtualenv("r-yolo-env", required = TRUE)

# 4. Import ultralytics
ultralytics <- import("ultralytics")

# Train model
# Load existing best weights if available to speed up training, otherwise start from scratch
best_weights <- file.path(getwd(), "runs", "detect", "train", "weights", "best.pt")

if (file.exists(best_weights)) {
    model <- ultralytics$YOLO(best_weights)
    epochs_to_run <- 20L  # Fast fine-tuning on new data
} else {
    model <- ultralytics$YOLO("yolov8n.pt")
    epochs_to_run <- 50L  # Baseline initialization
}

model$train(
    data     = file.path(getwd(), "dataset", "data.yaml"),
    project  = file.path(getwd(), "runs", "detect"),
    name     = "train",
    epochs   = epochs_to_run,
    imgsz    = 640L,
    device   = "mps",  # Uses Mac GPU acceleration
    exist_ok = TRUE    # Overwrite the train folder instead of creating train2, train3, etc.
)
