from flask import Flask, request, jsonify
import torch
from PIL import Image
import io
from ultralytics import YOLO

app = Flask(__name__)

# Load YOLO models
model_80_classes = YOLO('yolo11n.pt')  # Mô hình cho 80 lớp
model_paraglider = YOLO('best.pt')      # Mô hình cho lớp paraglider
model_80_classes.eval()
model_paraglider.eval()

# Dictionary to map class indices to names for 80 classes
class_names_80 = {0: 'person', 1: 'bicycle', 2: 'car', 3: 'motorcycle', 4: 'airplane',
               5: 'bus', 6: 'train', 7: 'truck', 8: 'boat', 9: 'traffic light', 10: 'fire hydrant',
               11: 'stop sign', 12: 'parking meter', 13: 'bench', 14: 'bird', 15: 'cat',
               16: 'dog', 17: 'horse', 18: 'sheep', 19: 'cow', 20: 'elephant', 21: 'bear',
               22: 'zebra', 23: 'giraffe', 24: 'backpack', 25: 'umbrella', 26: 'handbag',
               27: 'tie', 28: 'suitcase', 29: 'frisbee', 30: 'skis', 31: 'snowboard',
               32: 'sports ball', 33: 'kite', 34: 'baseball bat', 35: 'baseball glove',
               36: 'skateboard', 37: 'surfboard', 38: 'tennis racket', 39: 'bottle',
               40: 'wine glass', 41: 'cup', 42: 'fork', 43: 'knife', 44: 'spoon', 45: 'bowl',
               46: 'banana', 47: 'apple', 48: 'sandwich', 49: 'orange', 50: 'broccoli',
               51: 'carrot', 52: 'hot dog', 53: 'pizza', 54: 'donut', 55: 'cake', 56: 'chair',
               57: 'couch', 58: 'potted plant', 59: 'bed', 60: 'dining table', 61: 'toilet',
               62: 'tv', 63: 'laptop', 64: 'mouse', 65: 'remote', 66: 'keyboard', 67: 'cell phone',
               68: 'microwave', 69: 'oven', 70: 'toaster', 71: 'sink', 72: 'refrigerator',
               73: 'book', 74: 'clock', 75: 'vase', 76: 'scissors', 77: 'teddy bear', 78: 'hair drier',
               79: 'toothbrush'}  # Thêm tất cả 80 lớp vào đây
class_names_paraglider = {0: 'paraglider'}  # Lớp mới

@app.route('/detect', methods=['POST'])
def detect():
    if 'image' not in request.files:
        return jsonify({'error': 'No image file'}), 400

    image_file = request.files['image']
    image_bytes = image_file.read()
    image = Image.open(io.BytesIO(image_bytes))

    # Perform inference for 80 classes
    results_80 = model_80_classes(image)
    detections_80 = process_results(results_80, class_names_80, image)

    # Perform inference for paraglider
    results_paraglider = model_paraglider(image)
    detections_paraglider = process_results(results_paraglider, class_names_paraglider, image)

    # Combine detections
    all_detections = detections_80 + detections_paraglider

    return jsonify({'detections': all_detections})

def process_results(results, class_names, image):
    detections = []
    for result in results:
        for box in result.boxes.data.tolist():
            x1, y1, x2, y2, conf, cls = box
            detection = {
                'name': class_names.get(int(cls), 'unknown'),
                'x': x1,
                'y': y1,
                'width': x2 - x1,
                'height': y2 - y1,
                'confidence': conf,
                'original_width': image.width,
                'original_height': image.height
            }
            detections.append(detection)
    return detections

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
