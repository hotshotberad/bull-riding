######
# Now that model is trained, I can start a basic workflow. Start by adding the new url to this script and running it, then run script 4 to auto label the new video, then run script 2 to review them, then finally run script 3 to update the model.
######

# Load required packages
library(av) # working with video and audio (will use to extract still image frames from videos)
library(fs) # manage files and folders (create directories, delete files)

# The video link we want to download and slice up.
url <- "https://youtu.be/vILCvdcg8rk?si=J3_xvg84QtkGGvuy"

# What time to stop the function from extracting images (e.g. buck off time)
trim <- "0:15"

# Define the extraction function
## Extract still images from video

extract_frames <- function(video_url,
                           output_dir = "/Users/bradley/Desktop/coding/projects/bull",
                           video_name = "ride_raw.mp4",
                           fps = 2,
                           trim = NULL) {

    # 1. Setup Folders and Paths
    ## Specify where the downloaded video and extracted images should be saved.
    raw_video_dir <- file.path(output_dir, "raw_video")
    frames_dir    <- file.path(output_dir, "images")
    ## Automatically create the folders if they don't already exist on your computer.

    #fs::dir_create(raw_video_dir)
    #fs::dir_create(frames_dir)

    ## Combine the folder path and file name into one full path for the video file.
    raw_video_path <- file.path(raw_video_dir, video_name)

    ## Replace old video if one exists
    if (file_exists(raw_video_path)) {
        file_delete(raw_video_path)
    }

    # 2. Download the video
    # Print status message to console
    message("Downloading video from YouTube...")

    # "system2" lets R talk to external software installed on your computer.
    # Here, it runs "yt-dlp" (a command-line video downloader tool) with specific settings:
    # - Grab the best quality video/audio format compatible with MP4.
    # - Save it under the path we set earlier (raw_video_path).
    download_cmd <- system2(
        command = "yt-dlp",
        args = c(
            "-f", "bestvideo[vcodec^=avc]+bestaudio[ext=m4a]/best[vcodec^=avc]/best",
            "--merge-output-format", "mp4",
            "-o", raw_video_path,
            video_url
        ),
        stdout = TRUE,  # Capture regular output messages from yt-dlp
        stderr = TRUE   # Capture any error messages from yt-dlp
    )

    ## Safety check: If the video file didn't actually download, stop the script and display the error log.
    if (!file.exists(raw_video_path)) {
        stop("Video download failed. Output log:\n", paste(download_cmd, collapse = "\n"))
    }

    # 3. Extract still image frames from the video
    message("Extracting still frames at fps = ", fps, "...")

    # Slice the downloaded MP4 into individual frame files:
    extracted_files <- av::av_video_images(
        video   = raw_video_path,
        destdir = frames_dir,
        format  = "jpg",
        fps     = fps,
        trim    = trim
    )

    message("Successfully extracted ", length(extracted_files), " frames to: ", frames_dir)

    # Return the list of created image file paths quietly (without cluttering the console).
    return(invisible(extracted_files))
}

frames <- extract_frames(
    video_url = url,
    output_dir  = "/Users/bradley/Desktop/coding/projects/bull",
    fps         = 2,
    trim        = trim
)
