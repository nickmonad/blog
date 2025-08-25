flox:
    flox activate -- fish

build:
    tailwindcss -c tailwind.config.js -i static/style.tailwind.css -o static/style.css --minify
    zola build

dev:
    DEV=true zola serve
