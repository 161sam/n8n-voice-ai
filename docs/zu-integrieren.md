## Convert Text to Speech with Local KOKORO TTS

[**Workflow TEMPLATE**](https://n8n.io/workflows/3547-convert-text-to-speech-with-local-kokoro-tts/)

---

You can set up a working n8n automation workflow.

Unfortunately, we can’t interact with the KOKORO API via browser URL (GET/POST), but we can run a Python script through n8n and pass any variables to it.

In the tutorial, the D drive is used, but you can rewrite this for any paths, including the C drive.

Let’s go!

n8n index screen UI
 
Step 1 

You need to have Python installed.

Also, download and extract the portable version of KOKORO from GitHub.

Create a file named voicegen.py with the following code in the KOKORO folder (C:\KOKORO). As you can see, the output path is: D:\output.mp3.

voicegen.py script

 

Thank you, Chat GPT!

 

import sys
import shutil
from gradio_client import Client

# Set UTF-8 encoding for stdout
sys.stdout.reconfigure(encoding=’utf-8′)

# Get arguments from command line
text = sys.argv[1] # First argument: input text
voice = sys.argv[2] # Second argument: voice
speed = float(sys.argv[3]) # Third argument: speed (converted to float)

print(f”Received text: {text}”)
print(f”Voice: {voice}”)
print(f”Speed: {speed}”)

# Connect to local Gradio server
client = Client(“http://localhost:7860/”)

# Generate speech using the API
result = client.predict(
text=text,
voice=voice,
speed=speed,
api_name=”/generate_speech”
)

# Define output path
output_path = r”D:\output.mp3″

# Move the generated file
shutil.move(result[1], output_path)

# Print output path
print(output_path)

 
Step 2

Go to n8n and create the following workflow.

n8n index screen UI    
 
Step 3

Edit Field Module.

n8n + KOKORO TTS Integration Step  

 
Step 4

We’ll need an Execute Command module with the command: python C:\KOKORO\voicegen.py “{{ $json.text }}” “{{ $json.voice }}” 1

n8n + KOKORO TTS Integration Step    

 
Step 5

The script is already working, but to listen to it, you can connect a Binary module with the path to the generated MP3 file D:/output.mp3

n8n + KOKORO TTS Integration Step    

 
Step 6

Click “Text workflow” and enjoy the result.

There are more voices and accents than in ChatGPT, plus it’s free.
Video Player
00:00
00:04

 
American English Voices

    Female (af_*):
        af_alloy: Alloy – Clear and professional
        af_aoede: Aoede – Smooth and melodic
        af_bella: Bella – Warm and friendly
        af_jessica: Jessica – Natural and engaging
        af_kore: Kore – Bright and energetic
        af_nicole: Nicole – Professional and articulate
        af_nova: Nova – Modern and dynamic
        af_river: River – Soft and flowing
        af_sarah: Sarah – Casual and approachable
        af_sky: Sky – Light and airy
    Male (am_*):
        am_adam: Adam – Strong and confident
        am_echo: Echo – Resonant and clear
        am_eric: Eric – Professional and authoritative
        am_fenrir: Fenrir – Deep and powerful
        am_liam: Liam – Friendly and conversational
        am_michael: Michael – Warm and trustworthy
        am_onyx: Onyx – Rich and sophisticated
        am_puck: Puck – Playful and energetic

British English Voices

    Female (bf_*):
        bf_alice: Alice – Refined and elegant
        bf_emma: Emma – Warm and professional
        bf_isabella: Isabella – Sophisticated and clear
        bf_lily: Lily – Sweet and gentle
    Male (bm_*):
        bm_daniel: Daniel – Polished and professional
        bm_fable: Fable – Storytelling and engaging
        bm_george: George – Classic British accent
        bm_lewis: Lewis – Modern British accent

 
