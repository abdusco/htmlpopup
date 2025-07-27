# HTMLPopup

A simple macOS command-line utility to display HTML content or a URL in a native webview popup window.

## Usage

```bash
htmlpopup [OPTIONS] <html_content_or_file|directory|url|stdin>
```

### Arguments:
- Content can be provided as:
  - A string of HTML content, e.g., `<h1>Hello, World!</h1>`.
  - A path to a local HTML file, e.g., `my_page.html`.
  - A URL to a web page, e.g., `https://www.example.com`.
  - A directory path to serve static files, e.g., `./static/`.
  - `-` to read HTML content from stdin.

### Options:

*   `--title <title>`: Set the window title.
*   `--width <width>`: Set the window width (default: 800).
*   `--height <height>`: Set the window height (default: 600).
*   `--env <json_string>`: Provide a JSON string to be injected as `window.env` in the web view. This is useful for complex JSON structures.
*   `--env.<key> <value>`: Provide individual key-value pairs to be injected as `window.env`. Values are parsed as JSON (e.g., `true`, `123`, `"string"`, `[1,2]`, `{"a":1}`) if possible, otherwise they are treated as plain strings, but can be forced as string by quoting it `"str"`. This option can be used multiple times to set multiple environment variables.
*   `--version`: Display the application version.

### Examples:

```bash
# Display a simple HTML string
htmlpopup "<h1>Hello, World!</h1>"

# Display content from a local HTML file
htmlpopup my_page.html

# Display a website
htmlpopup https://www.example.com

# Read HTML from stdin
echo "<p>Content from stdin</p>" | htmlpopup -

# Serve a static directory by passing the directory path
htmlpopup ./static/

# Set window size and title
htmlpopup --width 1024 --height 768 --title "My Custom Window" my_page.html

# Inject environment variables
# Inject environment variables
htmlpopup --env '{"API_KEY": "old_key"}' --env.API_KEY "new_key" --env.DEBUG true --env.COUNT 123 --env.LIST '[1,2,3]' my_app.html
# In the above example, --env.API_KEY will override the API_KEY from --env.
# window.env will be: { "API_KEY": "new_key", "DEBUG": true, "COUNT": 123, "LIST": [1,2,3] }
```


## Features

*   Display HTML content from string, file, directory, or URL.
*   Configurable window title, width, and height.
*   Inject JSON environment variables into the web view (`window.env`).
*   Window can be pinned to stay on top.


## JavaScript API

When your HTML is loaded in the popup, the following JavaScript objects are available in the webview:

### `window.env`

If you use the `--env` option, the provided JSON is injected as `window.env` at the start of every page load, before anything is executed. For example:

```js
console.log(window.env); // { API_KEY: "123", DEBUG: true }
```

### `window.app`

The following methods are available on `window.app`:

- `app.finish(message)`: Closes the popup window and prints `message` to stdout. Useful when you run the app from a script and want to capture the result.
- `app.setSize(width, height)`: Sets the window size in pixels.
- `app.setFullscreen(enabled)`: Toggles fullscreen mode (`enabled` is a boolean).
- `app.setFloating(enabled)`: Pins or unpins the window on top (`enabled` is a boolean).
- `app.selectFolder()`: Opens a folder picker dialog. Returns a Promise that resolves to the selected folder path (the real path on the disk), or rejects if cancelled.

#### Example usage:

```js
// Close the window and print a message
window.app.finish("Done!");

// Resize the window
window.app.setSize(1024, 800);

// Toggle fullscreen
window.app.setFullscreen(true);

// Pin the window on top
window.app.setFloating(true);

// Select a folder
window.app.selectFolder().then(path => {
  console.log("Selected folder:", path);
}).catch(err => {
  console.log("Selection cancelled");
});
```


## Build and Run

To build the application, you need `swiftc` installed on your macOS system. Make sure you have the latest version of Xcode and the command line tools installed.

Navigate to the project root and run:

```bash
ARCH=arm64 VERSION=1.2.3 ./build.sh
```

This command compiles the `HTMLPopup.swift` file and links the necessary macOS frameworks.

To run the compiled executable:

```bash
./htmlpopup-arm64 "<h1>Hello from local build!</h1>"
```


## Compatibility

Tested on macOS Ventura 13.3.1 (a) (22E772610a).
