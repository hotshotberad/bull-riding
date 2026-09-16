# Load required pipeline scripts and utilities
source("1_video_image_extraction.R")

# 1. Prompt user for video inputs
video_url <- "https://youtu.be/AmCSC0i1KC4?si=chFMPj1O1XUrnvrD"
trim_time <- "0:16"

if (trim_time == "") {
    trim_time <- NULL
}

# 2. Step 1: Download video and extract image frames
message("\n--- Step 1: Ingesting Video ---")
extract_frames(
    video_url  = video_url,
    output_dir = getwd(),
    fps        = 2,
    trim       = trim_time
)
message("\n--- Step 1 Complete! ---")

# 3. Step 2: Sample frames and generate candidate YOLO labels
message("\n--- Step 2: Generating AI Labels ---")
source("4_auto_label_pipeline.R")
message("\n--- Step 2 Complete! ---")

# 4. Step 3: Launch Shiny interface for human review and box adjustment
message("\n--- Step 3: Launching Label Review App ---")
message("Review the images, click Approve, and stop/close the app when finished.\n")

# Explicitly evaluate and launch the Shiny app instance
app_env <- new.env()
sys.source("2_new_image_classification.R", envir = app_env)
shiny::runApp(shiny::shinyApp(ui = app_env$ui, server = app_env$server))
message("\n--- Step 3 Complete! ---")





# 5. Step 4: Retrain model on newly approved labels
message("\n--- Step 4: Retraining Model ---")
source("3_model_setup.R")
message("\nWorkflow complete! Model updated.")
