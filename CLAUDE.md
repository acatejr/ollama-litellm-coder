# ollama-litellm-coder

A project for building a droplet on DigitalOcean that uses docker to install and run Ollama and litellm.  Ollama runs qwen2.5-coder:3b.  This project is supposed to run the model as fast as possible.  The goal of the project is to show that ollama and qwen2.5-coder:3b can be used as a suitable AI coding agent.  This should help an organization minimize AI costs and maybe keep a bit more privacy.

## Context
Claude is a infrastructere and software development expert asked to proivd guidance on this project.

## Rules for Claude
- Honor the .gitignore file.
- Never readh any file that has 'env' in the file name.
- Ignore all tmp folders.
- Ingore the .venv folder (aka all python virtual environments)
