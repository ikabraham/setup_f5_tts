#!/bin/bash

set -e

# --- GCP-specific initialization ---
echo "Starting GCP setup process..."

# Install system updates and requirements
sudo apt-get update
sudo apt-get install -y \
    git \
    build-essential \
    python3-dev \
    python3-venv \
    libasound2-dev \
    portaudio19-dev \
    ffmpeg

# Create a virtual environment
python3 -m venv venv
source venv/bin/activate

# Check python version
echo "Python version: $(python --version)"

# Install required Python packages
pip install --upgrade pip
pip install --timeout 60 numpy
pip install --timeout 60 torch torchaudio
pip install --timeout 60 flask soundfile
pip install requests google-cloud-logging

# Clone F5-TTS repository if it doesn't exist
if [ ! -d "F5-TTS" ]; then
    echo "Cloning F5-TTS repository..."
    git clone https://github.com/SWivid/F5-TTS.git
else
    echo "F5-TTS repository already exists, skipping clone."
fi

# Navigate to the F5-TTS directory and install
cd F5-TTS
pip uninstall -y f5-tts
pip install -e .
cd ..

# --- GCP Application Setup ---
# Create the Flask API server with GCP logging
cat << 'EOF' > api_server.py
import sys
import os
sys.path.append(os.path.join(os.getcwd(), 'F5-TTS', 'src'))
from flask import Flask, request, send_file
from f5_tts.api import F5TTS
import io
import soundfile as sf
import requests
from google.cloud import logging

# Initialize Google Cloud Logging
logging_client = logging.Client()
logger = logging_client.logger('f5tts-api')

app = Flask(__name__)
try:
    tts = F5TTS()
    logger.log_text('F5TTS initialized successfully')
except Exception as e:
    logger.log_text(f'Error initializing F5TTS: {e}', severity='ERROR')
    exit(1)

@app.route('/synthesize', methods=['POST'])
def synthesize():
    try:
        data = request.get_json()
        if not data:
            logger.log_text('No JSON payload provided', severity='WARNING')
            return {'error': 'No JSON payload provided'}, 400

        text = data.get('text')
        ref_file_url = data.get('ref_file')
        ref_text = data.get('ref_text', "")

        if not text:
            logger.log_text('No text provided in JSON', severity='WARNING')
            return {'error': 'No text provided in JSON'}, 400

        if not ref_file_url:
            logger.log_text('No ref_file provided in JSON', severity='WARNING')
            return {'error': 'No ref_file provided in JSON'}, 400

        # Download ref_file
        try:
            response = requests.get(ref_file_url)
            response.raise_for_status()
            ref_file_path = 'ref_audio.wav'
            with open(ref_file_path, 'wb') as f:
                f.write(response.content)
        except Exception as e:
            logger.log_text(f'Error downloading ref_file: {e}', severity='ERROR')
            return {'error': f'Error downloading ref_file: {e}'}, 400

        wav, sr, spect = tts.infer(
            ref_file=ref_file_path,
            ref_text=ref_text,
            gen_text=text,
        )
        buffer = io.BytesIO()
        sf.write(buffer, wav, sr, format='WAV')
        buffer.seek(0)
        logger.log_text('Successfully synthesized audio')
        return send_file(buffer, mimetype='audio/wav')
    except Exception as e:
        logger.log_text(f'Error during synthesis: {e}', severity='ERROR')
        return {'error': str(e)}, 500

@app.route('/health', methods=['GET'])
def health():
    logger.log_text('Health check requested')
    return {'status': 'healthy'}, 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))  # GCP App Engine expects port 8080
    app.run(host='0.0.0.0', port=port)
EOF

# Create systemd service file for automatic startup
sudo cat << 'EOF' > /etc/systemd/system/f5tts.service
[Unit]
Description=F5 TTS API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment=PATH=/root/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/root/venv/bin/python /root/api_server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl enable f5tts
sudo systemctl start f5tts

echo "GCP Setup complete!"
