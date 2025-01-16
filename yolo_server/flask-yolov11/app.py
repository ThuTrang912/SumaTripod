from flask import Flask, request, jsonify, render_template
from ultralytics import YOLO
from PIL import Image

app = Flask(__name__)

# Load the trained YOLO model
model = YOLO('best.pt')  # Path to your trained model

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/predict', methods=['POST'])
def predict():
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'})
    
    file = request.files['file']
    img = Image.open(file)
    
    # Perform prediction
    results = model(img)
    detections = results[0].boxes  # Get bounding box predictions

    output = []
    for box in detections:
        output.append({
            'class': box.cls,
            'confidence': box.conf,
            'coordinates': box.xywh.tolist()  # x, y, width, height
        })

    return jsonify(output)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

