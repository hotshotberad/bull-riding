# The purpose of this code is to extract still images from video URLs which will then be used to train a YOLO model for object detection. The code creates a function that downloads a video from a given URL, saves it to a specified directory, and extracts still image frames at a specified rate in frames per second (fps). It also handles trimming the video if a trim time is provided.

# Load required packages
library(av) # extracts still image frames from videos
library(fs) # create directories, delete files

##########
# This section is not used when using the "0_run_workflow.R" script.

# The video link to download extract images from.
#url <- "https://youtu.be/P9JyBBQ0SdQ?si=MUa_KWyBlCXzMfRP"

# What time to stop the function from extracting images (e.g. buck off time)
#trim <- "0:15"
##########

# Helper function to convert "MM:SS", "HH:MM:SS", or numeric strings to total seconds

parse_to_seconds <- function(t) {
    if (is.null(t) || is.na(t) || trimws(t) == "") return(NULL)
    if (is.numeric(t)) return(as.numeric(t))

    parts <- as.numeric(strsplit(trimws(t), ":")[[1]])
    if (length(parts) == 1) {
        return(parts[1])
    } else if (length(parts) == 2) {
        return(parts[1] * 60 + parts[2])
    } else if (length(parts) == 3) {
        return(parts[1] * 3600 + parts[2] * 60 + parts[3])
    } else {
        stop("Invalid time format: ", t)
    }
}

# Define and create the extraction function
## Extract still images from video

extract_frames <- function(video_url,
                           output_dir = "/Users/bradley/Desktop/coding/projects/bull",
                           video_name = "ride_raw.mp4",
                           fps = 2,
                           start_time = NULL,
                           end_time = NULL) {

    # 1. Setup Folders and Paths
    raw_video_dir <- file.path(output_dir, "raw_video")
    frames_dir    <- file.path(output_dir, "images")

    if (dir_exists(frames_dir)) {
        dir_delete(frames_dir)
    }
    dir_create(frames_dir)

    if (!dir_exists(raw_video_dir)) {
        dir_create(raw_video_dir)
    }

    raw_video_path     <- file.path(raw_video_dir, video_name)
    trimmed_video_path <- file.path(raw_video_dir, "ride_trimmed.mp4")

    if (file_exists(raw_video_path))     file_delete(raw_video_path)
    if (file_exists(trimmed_video_path)) file_delete(trimmed_video_path)

    # 2. Download the video
    message("Downloading video...")
    download_cmd <- system2(
        command = "yt-dlp",
        args = c(
            "-f", "bestvideo[vcodec^=avc]+bestaudio[ext=m4a]/best[vcodec^=avc]/best",
            "--merge-output-format", "mp4",
            "-o", raw_video_path,
            video_url
        ),
        stdout = TRUE,
        stderr = TRUE
    )

    if (!file.exists(raw_video_path)) {
        stop("Video download failed. Output log:\n", paste(download_cmd, collapse = "\n"))
    }

    # 3. Calculate start and duration
    start_sec <- parse_to_seconds(start_time)
    end_sec   <- parse_to_seconds(end_time)

    target_video <- raw_video_path

    # If timing bounds are provided, cut the video before extracting images
    if (!is.null(start_sec) || !is.null(end_sec)) {
        s_pos <- ifelse(is.null(start_sec), 0, start_sec)

        ffmpeg_args <- c("-y", "-ss", as.character(s_pos))
        if (!is.null(end_sec)) {
            duration <- end_sec - s_pos
            ffmpeg_args <- c(ffmpeg_args, "-t", as.character(duration))
        }

        ffmpeg_args <- c(ffmpeg_args, "-i", raw_video_path, "-c", "copy", trimmed_video_path)

        message(sprintf("Trimming video from %.1fs to %s...",
                        s_pos, ifelse(is.null(end_sec), "end", sprintf("%.1fs", end_sec))))

        system2("ffmpeg", args = ffmpeg_args, stdout = FALSE, stderr = FALSE)

        if (file.exists(trimmed_video_path) && file_info(trimmed_video_path)$size > 0) {
            target_video <- trimmed_video_path
        }
    }

    # 4. Extract frames from the targeted clip
    message("Extracting still frames at fps = ", fps, "...")
    extracted_files <- av::av_video_images(
        video   = target_video,
        destdir = frames_dir,
        format  = "jpg",
        fps     = fps
    )

    message("Successfully extracted ", length(extracted_files), " frames to: ", frames_dir)
}