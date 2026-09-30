# Proof-of-concept script to talk to qwen2.5-coder on the droplet through the LiteLLM proxy.
import os

from dotenv import load_dotenv
from litellm import completion

load_dotenv()  # reads .env in the current directory

API_BASE = os.environ.get("LITELLM_PROXY_API_BASE", "http://143.244.182.53:4000")  # e.g. http://<droplet-ip>:4000
API_KEY = os.environ["TF_VAR_litellm_api_key"]  # the key limited to qwen2.5-coder-3b
MODEL = "litellm_proxy/qwen2.5-coder-3b"  # litellm_proxy/<model_name from litellm-config.yaml>


def ask(prompt: str) -> str:
    response = completion(
        model=MODEL,
        api_base=API_BASE,
        api_key=API_KEY,
        messages=[
            {"role": "system", "content": "You are a concise coding assistant."},
            {"role": "user", "content": prompt},
        ],
        timeout=600,  # CPU inference is slow; the first reply can take a while
    )
    return response.choices[0].message.content


def ask_streaming(prompt: str) -> None:
    """Print the reply as it's generated, so you see progress on slow hardware."""
    stream = completion(
        model=MODEL,
        api_base=API_BASE,
        api_key=API_KEY,
        messages=[{"role": "user", "content": prompt}],
        stream=True,
        timeout=600,
    )
    for chunk in stream:
        print(chunk.choices[0].delta.content or "", end="", flush=True)
    print()


def main():
    print(ask("Write a Python function that reverses a string."))
    print("---")
    ask_streaming("Explain Python list comprehensions in two sentences.")
    
    print("---")
    print(ask("Tell me a joke about programming."))


if __name__ == "__main__":
    main()
