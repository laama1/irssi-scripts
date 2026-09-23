import re, sys
from contextlib import redirect_stderr
from os import devnull
from pathlib import Path
from youtube_transcript_api import YouTubeTranscriptApi
from openai import OpenAI
ytt_api = YouTubeTranscriptApi()
openai_api_key = Path("/home/laama/.irssi/scripts/franklin_api.key").read_text(encoding="utf-8").strip()
save_path = "/var/www/html/bot/youtube"
url = sys.argv[1]
vid = re.search(r"(?:v=|youtu\.be/)?([\w-]{11})", url).group(1)

with open(devnull, "w") as null_stderr:
    with redirect_stderr(null_stderr):
        subs = ytt_api.fetch(vid, languages=["fi", "en"])
text = " ".join(s.text for s in subs)
client = OpenAI(api_key=openai_api_key) 
res = client.chat.completions.create(
    model="gpt-4o-mini", 
    messages=[
        { "role": "user", "content": "Kerro videon pääpointit suomeksi bullet-listana:\n" + text[:60000] }
    ]
)
message_content = res.choices[0].message.content
with open(f"{save_path}/{vid}.txt", "w", encoding="utf-8") as output_file:
   output_file.write(message_content)

print(f"Transcript saved to {save_path}/{vid}.txt")