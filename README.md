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
*   File drag-and-drop support with `files-dropped` event.
*   File system access: read files, save files, select files/folders, reveal in Finder.
*   Automatic light/dark theme support with CSS variables and theme change events.
*   Rich JavaScript API for window control, file operations, and terminal output.


## JavaScript API

When your HTML is loaded in the popup, the following JavaScript objects and APIs are available in the webview:

### `window.env`

Custom environment variables that you can inject at startup using the `--env` or `--env.<key>` command-line options.

If you use the `--env` option, the provided JSON is injected as `window.env` at the start of every page load, before any scripts execute. For example:

```bash
htmlpopup --env '{"API_KEY":"123","DEBUG":true}' my_page.html
```

```js
console.log(window.env); // { API_KEY: "123", DEBUG: true }
```

Individual environment variables can also be set with `--env.<key>`:

```bash
htmlpopup --env.API_KEY "my-key" --env.DEBUG true my_page.html
```

### `window.app`

The `window.app` object provides methods to interact with the native window and file system.

#### Window Control Methods

- **`app.finish(message)`**  
  Closes the popup window and prints `message` to stdout. Useful when running the app from a script to capture output.
  
  ```js
  window.app.finish("Processing complete!");
  ```

- **`app.setSize(width, height)`**  
  Sets the window size in pixels.
  
  ```js
  window.app.setSize(1024, 768);
  ```

- **`app.setFullscreen(enabled)`**  
  Toggles fullscreen mode. `enabled` is a boolean.
  
  ```js
  window.app.setFullscreen(true);  // Enter fullscreen
  window.app.setFullscreen(false); // Exit fullscreen
  ```

- **`app.setFloating(enabled)`**  
  Pins or unpins the window to stay on top of other windows. `enabled` is a boolean.
  
  ```js
  window.app.setFloating(true);  // Pin on top
  window.app.setFloating(false); // Unpin
  ```

- **`app.setTitle(title)`**  
  Sets the window title.
  
  ```js
  window.app.setTitle("My Custom Title");
  ```

#### File System Methods

All file system methods return Promises that resolve with the result or reject on error/cancellation.

- **`app.selectFolder()`**  
  Opens a native folder picker dialog. Returns a Promise that resolves to the selected folder path (absolute path on disk), or rejects if the user cancels.
  
  ```js
  window.app.selectFolder()
    .then(path => console.log("Selected folder:", path))
    .catch(() => console.log("Selection cancelled"));
  ```

- **`app.selectFile(options)`**  
  Opens a native file picker dialog. Returns a Promise that resolves to the selected file path (or array of paths if multiple selection is enabled), or rejects if cancelled.
  
  **Options** (all optional):
  - `canChooseFiles` (boolean, default: `true`): Allow selecting files
  - `canChooseDirectories` (boolean, default: `false`): Allow selecting directories
  - `allowsMultipleSelection` (boolean, default: `false`): Allow selecting multiple items
  - `allowedFileTypes` (array of strings, optional): Filter by file extensions (e.g., `["txt", "pdf"]`)
  
  ```js
  // Select a single file
  window.app.selectFile()
    .then(path => console.log("Selected:", path));
  
  // Select multiple text or PDF files
  window.app.selectFile({
    allowsMultipleSelection: true,
    allowedFileTypes: ["txt", "pdf"]
  }).then(paths => console.log("Selected files:", paths));
  ```

- **`app.saveFile(content, fileName)`**  
  Opens a native save dialog. Returns a Promise that resolves to the saved file path, or rejects if cancelled.
  - `content` (string): The file content to save
  - `fileName` (string, optional): Default filename for the save dialog
  
  ```js
  window.app.saveFile("Hello, World!", "greeting.txt")
    .then(path => console.log("Saved to:", path))
    .catch(() => console.log("Save cancelled"));
  ```

- **`app.readFile(filePath)`**  
  Reads a file as text. Returns a Promise that resolves to the file content as a string, or rejects on error.
  
  ```js
  window.app.readFile("/path/to/file.txt")
    .then(content => console.log("File content:", content))
    .catch(err => console.error("Read error:", err));
  ```

- **`app.readFileAsDataURL(filePath)`**  
  Reads a file and returns it as a Data URL (base64-encoded). Useful for images and binary files. Returns a Promise that resolves to the Data URL string, or rejects on error.
  
  ```js
  window.app.readFileAsDataURL("/path/to/image.png")
    .then(dataURL => {
      const img = document.createElement("img");
      img.src = dataURL;
      document.body.appendChild(img);
    });
  ```

- **`app.revealInFinder(path)`**  
  Opens Finder and reveals the file or folder at the given path.
  
  ```js
  window.app.revealInFinder("/tmp");
  ```

#### Terminal Output Methods

- **`app.writeLine(text)`**  
  Prints a line of text to stdout. Useful for logging or outputting data from JavaScript to the terminal.
  
  ```js
  window.app.writeLine("Hello from JavaScript!");
  window.app.writeLine("This appears in the terminal");
  ```

#### Theme Support

- **`app.theme`**  
  A read-only string property containing the current system theme: `"light"` or `"dark"`.
  
  ```js
  console.log("Current theme:", window.app.theme); // "light" or "dark"
  ```

### Events

#### `files-dropped` Event

The webview supports drag-and-drop file operations. When files are dropped onto the window, a `files-dropped` custom event is dispatched with the file paths:

```js
window.addEventListener('files-dropped', function(event) {
  const files = event.detail.files; // Array of file paths (strings)
  console.log('Dropped files:', files);
  
  // Read the first dropped file
  if (files.length > 0) {
    window.app.readFile(files[0]).then(content => {
      console.log('File content:', content);
    });
  }
});
```

**Note:** Dropping files will not navigate to the file. The drop is handled by the app and triggers the `files-dropped` event instead.

#### `themechange` Event

When the system appearance changes between light and dark mode, a `themechange` custom event is dispatched:

```js
window.addEventListener('themechange', function(event) {
  const theme = event.detail.theme; // "light" or "dark"
  console.log('Theme changed to:', theme);
  
  // The window.app.theme property is also updated
  console.log('Current theme:', window.app.theme);
});
```

The document element automatically receives:
- A `data-theme` attribute set to `"light"` or `"dark"`
- A `.dark` class when in dark mode

### CSS Variables

HTMLPopup provides theme-aware CSS custom properties that automatically adapt to the system appearance:

```css
:root {
  --htmlpopup-background: #ffffff;   /* Background color */
  --htmlpopup-text: #1c1c1e;         /* Text color */
  --htmlpopup-border: #d1d1d6;       /* Border color */
  --htmlpopup-surface: rgba(249, 249, 251, 0.9);  /* Surface/card background */
  --htmlpopup-link: #0a84ff;         /* Link color */
  --htmlpopup-muted: #6e6e73;        /* Muted/secondary text color */
}
```

In dark mode, these variables automatically update to appropriate dark theme colors.

**Using the CSS variables:**

```css
body {
  background-color: var(--htmlpopup-background);
  color: var(--htmlpopup-text);
}

.card {
  background-color: var(--htmlpopup-surface);
  border: 1px solid var(--htmlpopup-border);
}

a {
  color: var(--htmlpopup-link);
}
```

**Responding to theme manually:**

```css
/* Light mode specific styles */
:root[data-theme='light'] .my-element {
  /* ... */
}

/* Dark mode specific styles */
:root[data-theme='dark'] .my-element,
.dark .my-element {
  /* ... */
}
```

### Example Usage

```js
// Close the window and print a message
window.app.finish("Done!");

// Resize the window
window.app.setSize(1024, 800);

// Toggle fullscreen
window.app.setFullscreen(true);

// Pin the window on top
window.app.setFloating(true);

// Change the window title
window.app.setTitle("New Title");

// Select a folder
window.app.selectFolder().then(path => {
  console.log("Selected folder:", path);
}).catch(() => {
  console.log("Selection cancelled");
});

// Select multiple files with type filter
window.app.selectFile({
  allowsMultipleSelection: true,
  allowedFileTypes: ["txt", "pdf", "md"]
}).then(paths => {
  console.log("Selected files:", paths);
});

// Save a file
window.app.saveFile("Hello, World!", "greeting.txt").then(path => {
  console.log("Saved to:", path);
});

// Read a file as text
window.app.readFile("/path/to/file.txt").then(content => {
  console.log("File content:", content);
});

// Read an image as Data URL
window.app.readFileAsDataURL("/path/to/image.png").then(dataURL => {
  const img = document.createElement("img");
  img.src = dataURL;
  document.body.appendChild(img);
});

// Write to terminal
window.app.writeLine("Hello from JavaScript!");

// Reveal a file in Finder
window.app.revealInFinder("/tmp");

// Check current theme
console.log("Current theme:", window.app.theme);

// Listen for theme changes
window.addEventListener('themechange', (event) => {
  console.log("Theme changed to:", event.detail.theme);
});

// Listen for dropped files
window.addEventListener('files-dropped', (event) => {
  console.log("Dropped files:", event.detail.files);
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
