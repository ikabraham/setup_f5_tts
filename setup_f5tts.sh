#!/bin/bash

set -e

# --- Preparation Phase ---
echo "Starting setup process..."

# Install git and build essentials
apt-get update
apt-get install -y git build-essential python3-dev libasound2-dev portaudio19-dev

# Create a virtual environment
python3 -m venv venv
source venv/bin/activate

# Check python version
echo "Python version: $(python --version)"

# Install required Python packages (with increased timeout)
pip install --upgrade pip
pip install --timeout 60 numpy
pip install --timeout 60 torch torchaudio
pip install --timeout 60 flask soundfile
pip install requests


# Check if F5-TTS directory exists and clone if it doesn't
if [ ! -d "F5-TTS" ]; then
  echo "Cloning F5-TTS repository..."
  git clone https://github.com/SWivid/F5-TTS.git
else
  echo "F5-TTS repository already exists, skipping clone."
fi

# Navigate to the F5-TTS directory
cd F5-TTS

# Uninstall f5-tts in case it was installed in a previous run
echo "Uninstalling f5-tts (if installed)..."
pip uninstall -y f5-tts

# Install f5-tts in editable mode from source directory
echo "Installing f5-tts in editable mode..."
pip install -e .

# Go back to the root directory
cd ..

# Export all environment variables to /etc/environment (for SSH sessions)
env >> /etc/environment

# --- Application Phase ---
# Check if we are in an autoscaling group.
if [ -z "$VAST_AUTOSCALE_ENABLED" ]; then
    # Create a simple test script to verify installation
    cat << 'EOF' > test_f5tts.py
import sys
import os
sys.path.append(os.path.join(os.getcwd(), 'F5-TTS', 'src'))
from f5_tts.api import F5TTS

try:
    tts = F5TTS()
    text = "Hello, this is a test of F5 TTS."

    # Use a default audio file path
    example_audio_path = os.path.join(os.getcwd(), 'F5-TTS', 'src', 'f5_tts', 'infer', 'examples', 'basic', 'basic_ref_en.wav')

    wav, sr, spect = tts.infer(
        ref_file=example_audio_path,
        ref_text="This is a test.",
        gen_text=text,
        file_wave="test_output.wav",
        seed=-1,  # random seed = -1
    )

    print("Test complete - check for test_output.wav")
except Exception as e:
    print(f"Error during test: {e}")
    exit(1)
EOF

    # Run the test script
    echo "Running test script..."
    python test_f5tts.py
else
   echo "Skipping test as we are in an autoscaling group..."
fi

# Set up the Flask API server
cat << 'EOF' > api_server.py
import sys
import os
sys.path.append(os.path.join(os.getcwd(), 'F5-TTS', 'src'))
from flask import Flask, request, send_file
from f5_tts.api import F5TTS
import io
import soundfile as sf
import os
import requests

app = Flask(__name__)
try:
    tts = F5TTS()
except Exception as e:
    print(f"Error initializing F5TTS: {e}")
    exit(1)


@app.route('/synthesize', methods=['POST'])
def synthesize():
    try:
        data = request.get_json()
        if not data:
           return {'error': 'No JSON payload provided'}, 400
        text = data.get('text')
        ref_file_url = data.get('ref_file')
        ref_text = data.get('ref_text', "")

        if not text:
            return {'error': 'No text provided in JSON'}, 400
        
        if not ref_file_url:
            return {'error': 'No ref_file provided in JSON'}, 400

        # Download ref_file if not None
        try:
            response = requests.get(ref_file_url)
            response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
            ref_file_path = 'ref_audio.wav'
            with open(ref_file_path, 'wb') as f:
              f.write(response.content)
        except requests.exceptions.RequestException as e:
            return {'error': f'Error downloading ref_file: {e}'}, 400

        wav, sr, spect = tts.infer(
             ref_file=ref_file_path,
             ref_text=ref_text,
             gen_text=text,
        )
        buffer = io.BytesIO()
        sf.write(buffer, wav, sr, format='WAV')
        buffer.seek(0)
        return send_file(buffer, mimetype='audio/wav')
    except Exception as e:
        return {'error': str(e)}, 500

@app.route('/health', methods=['GET'])
def health():
    return {'status': 'healthy'}, 200

if __name__ == '__main__':
    # Determine the port from the environment variable, default to 7860
    port = int(os.environ.get('OPEN_BUTTON_PORT', 7860))
    app.run(host='0.0.0.0', port=port)
EOF

# Create a startup script
cat << 'EOF' > start_api.sh
#!/bin/bash
source venv/bin/activate
python api_server.py
EOF

chmod +x start_api.sh

# Start the API server
echo "Starting API server..."
./start_api.sh &

echo "Setup complete!"
