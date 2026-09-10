# Bull Riding Computer Vision: Detection & Tracking

An active learning computer vision pipeline designed to detect and track athletes and bucking bulls in professional bull riding footage. The repository implements an iterative labeling and training workflow built with **R**, **Shiny**, and **YOLOv8** via **Python/Reticulate**.

---

## Project Overview

Computer vision in rodeo sports faces significant challenges: rapid unpredictable movement, overlapping image targets (e.g. athletes sit on top of the bull with their legs on either side of the bull), complex camera angles, background noise in images (e.g. crowds and bullfighters), and arena dust. 

This project implements an Active Learning Loop (Extract, Auto-Annotate, Review, Retrain) to iteratively produce high-quality training datasets with minimal manual effort. As the model processes more rides, its detection accuracy increases, progressively reducing manual labeling overhead.

## Pipeline Workflow

The workflow is divided into four modular scripts executed in sequence:

**1_video_image_extraction.R**   --> Downloads raw YouTube ride & extracts frames

**4_auto_label_pipeline.R**      --> Samples frames & generates candidate YOLO bounding boxes

**2_new_image_classification.R** --> Interactive Shiny UI to verify/edit boxes & approve data

**3_model_setup.R**              --> Retrains YOLOv8 on newly approved annotations


* **1. Video Ingestion & Frame Extraction (`1_video_image_extraction.R`)**  
  Accepts a YouTube URL and an optional buckoff/whistle timestamp (`trim`). Downloads the clip using `yt-dlp` and extracts frame sequences at a designated frame rate (FPS) using the `av` package.

* **2. Auto-Annotation Inference (`4_auto_label_pipeline.R`)**  
  Samples target frames from the raw clip and passes them through the latest trained YOLO weights (`best.pt`). Generates pre-labeled bounding boxes for two target classes: **Cowboy (0)** and **Bull (1)**, saving label files directly into a staging queue.

* **3. Verification & Annotation UI (`2_new_image_classification.R`)**  
  Launches an interactive Shiny application to inspect model inferences. Allows users to drag-and-drop new bounding boxes, adjust faulty classes, undo single boxes, and push confirmed ground truth data directly into the training dataset folder.

* **4. Model Retraining (`3_model_setup.R`)**  
  Initializes an isolated Python environment through `reticulate` and fine-tunes the YOLOv8 neural network on the expanded set of verified images. The updated weights immediately become the baseline for the next video ingestion cycle).

---

## Prerequisites & Dependencies

* **R (4.5.2)** with packages: `shiny`, `bslib`, `magick`, `fs`, `av`, `reticulate`
* **External CLI Tool**: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) must be installed and accessible in your system `PATH`
* **Python Runtime**: Automatically handled via `3_model_setup.R` (`ultralytics`, `torch`, `torchvision`)

---

## Future Roadmap & Objectives

* **Contact & Impact Detection**: Classify direct collisions between the bull and the rider versus standard bucking motion.
* **Ground Fall & Hang-Up Recognition**: Track dangerous incidents such as rider hangs in the bull rope or heavy impact with the dirt.
* **Injury Prevention Analytics**: Quantify biomechanical movement and arena incident metrics to inform safety gear improvements and arena response times.
