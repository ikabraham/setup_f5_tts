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
