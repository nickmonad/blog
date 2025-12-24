flox:
    flox activate -- fish

tailwind:
    tailwindcss -c tailwind.config.js -i static/style.tailwind.css -o static/style.css --minify

build: tailwind
    zola build

serve: tailwind
    zola serve --drafts

dev:
    DEV=true zola serve --drafts
