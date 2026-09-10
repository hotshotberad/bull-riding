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
model <- ultralytics$YOLO("yolov8n.pt") # load pretrained nano weights
model$train(
    data    = "/Users/bradley/Desktop/coding/projects/bull/dataset/data.yaml",
    project = "/Users/bradley/Desktop/coding/projects/bull/runs/detect",
    name    = "train",
    epochs  = 50L,
    imgsz   = 640L
)