**Note:** After making the library above which works ok, I was thinking about other strategies to improve performance.  None of the following is implemented at this point, but if I put more time into this library, here as a reminder, and reference for strategies of improvement.

# **High-Performance Data Visualization Architecture in Elixir Phoenix LiveView: Constraints, Optimizations, and Integration Strategies**

## **Executive Summary**

The modern web application landscape is witnessing a paradigmatic shift towards server-centric state management, epitomized by the Elixir Phoenix LiveView framework. While this model offers profound benefits for developer productivity, consistency, and reduced client-side complexity, it introduces specific, non-trivial mechanical constraints when applied to the domain of high-performance data visualization. The rendering of complex, real-time datasets—whether financial tickers, telemetry dashboards, or scientific heatmaps—requires a rigorous analysis of the entire data pipeline, from the raw memory layout of tensors on the server to the pixel rasterization on the client’s Graphics Processing Unit (GPU).

This research report provides an exhaustive technical analysis of these constraints. We examine the architectural dichotomy between Server-Side Rendering (SSR) of visual artifacts and Client-Side Rendering (CSR) via transmitted data. We deconstruct the capabilities of the Elixir ecosystem, specifically the **Nx (Numerical Elixir)** library for tensor computation, **Evision** (OpenCV) for image processing, and **Rustler** for native integration. Simultaneously, we analyze the client-side performance envelope, contrasting the Document Object Model (DOM) limits against **HTML5 Canvas**, **WebGL**, and the emerging capabilities of **WebAssembly (WASM)**. By synthesizing benchmarks, architectural patterns, and library-specific behaviors (such as **uPlot**, **Tucan**, and **Contex**), this document establishes a comprehensive framework for engineering low-latency, high-cardinality visualization systems within the LiveView paradigm.

## **1\. The Theoretical Constraints of the LiveView Model in Visualization**

To engineer a robust solution, one must first accept the physical and logical constraints imposed by the Phoenix LiveView architecture. LiveView operates on the Actor Model, where each client connection acts as an isolated process on the BEAM (Erlang Virtual Machine). State is maintained on the server, and the user interface is a projection of that state, synchronized via a persistent WebSocket connection through the transmission of diffs.1

### **1.1 The Latency-Bandwidth Product and Interactivity**

In data visualization, latency is not merely a delay; it is a disconnect in cognitive continuity. The fundamental constraint of LiveView plotting is the **Round-Trip Time (RTT)**. Standard interactions in plotting libraries, such as hovering over a data point to reveal a tooltip or "brushing" a time range to zoom, typically rely on synchronous event loops within the browser's main thread.

When these interactions are lifted into the LiveView model, an event must travel from the client to the server, be processed by the LiveView process, result in a state change, trigger a re-render of the HEEx (HTML \+ EEx) template, pass through the diffing engine, undergo serialization, travel back over the wire, and finally be patched into the DOM by morphdom.1

The 100ms Threshold:  
Human perception perceives instantaneous response at latencies under 100ms. If the RTT plus processing time exceeds this, the visualization feels "sluggish." For a static chart, this is acceptable. For a real-time oscilloscope rendering 60 frames per second (16.6ms per frame), the standard LiveView request-response cycle is fundamentally too slow to drive the animation frame-by-frame. The constraint is, therefore, the decoupling of data delivery (which can be asynchronous and lagged) from rendering interaction (which must be synchronous and local).

### **1.2 The DOM Cardinality Bottleneck**

The second major constraint is the browser's Document Object Model. Libraries like **Contex** 2 or **D3.js** (in its SVG mode) represent data points as individual DOM nodes (\<circle\>, \<rect\>, \<path\>).

The "1,000 Node" Cliff:  
Browser layout engines are optimized for document flow, not massive vector graphics. As the number of data points ($N$) increases, the cost of DOM manipulation scales linearly or super-linearly depending on the CSS recalculations triggered.

* **Memory Overhead:** Each DOM node carries significant overhead (event listeners, style computation, layout box).  
* **Diffing Cost:** LiveView's diffing algorithm is highly optimized, using iodata and static/dynamic interleaving.4 However, diffing a list of 5,000 points to detect that one point has changed requires traversing the structure. Transmitting a diff for a large SVG, even if compressed, creates substantial serialization pressure on the CPU and bandwidth pressure on the network.

**Constraint Implication:** Pure SVG-based plotting via LiveView (SSR) is architecturally limited to low-cardinality datasets (typically $N \< 1,000$) or static reporting where update frequency is low (e.g., $\< 1 \\text{Hz}$).5

## **2\. The Server-Side Compute Engine: Nx and the GPU**

Moving beyond the transport layer, we encounter the constraints of data processing. The introduction of **Nx** has fundamentally altered Elixir's capability profile, transforming it from a language optimized for I/O and orchestration into a viable environment for numerical computing.7

### **2.1 Memory Layout and Tensor Efficiency**

Standard Elixir lists are linked lists. They provide $O(n)$ access time and poor cache locality. A list of 1 million floating-point numbers consumes roughly 16-32 MB of heap memory due to the overhead of tagged pointers and cons cells.

The Binary Advantage:  
Nx tensors are backed by Binaries—contiguous blocks of raw memory (byte arrays) managed by the BEAM. A tensor of 1 million 32-bit floats (f32) consumes exactly 4 MB of memory.9

* **Zero-Copy Operations:** When operating on these tensors using Nx functions, the data can be passed to Native Implemented Functions (NIFs) or external accelerators (like Google's XLA) without the expensive serialization/deserialization steps required for standard Erlang terms.  
* **Immutability vs. Performance:** Elixir is immutable. Naive manipulation of large tensors in a recursive loop would involve copying the entire binary for every step, leading to catastrophic performance. Nx solves this via Nx.Defn (Numerical Definitions). Functions defined with defn compile the entire operation sequence into a computation graph, which is then executed as a single, optimized native operation, bypassing the BEAM's immutability constraints for the duration of the calculation.10

### **2.2 GPU Acceleration with EXLA**

For visualizations requiring heavy pre-processing—such as generating a spectrogram from audio data, computing moving averages over massive financial datasets, or rendering fractal heatmaps—the CPU becomes the bottleneck. Nx's **EXLA** backend allows these computations to be offloaded to the GPU.11

Constraint 4: The Transfer Bottleneck (PCI-E)  
The constraint here is physics. While the GPU can perform matrix multiplications in nanoseconds, moving data from the Host (CPU RAM) to the Device (GPU VRAM) takes milliseconds over the PCI-E bus.

* **Small Data Penalty:** For a small plot (e.g., 100 data points), the overhead of initializing the XLA client and transferring the tensors outweighs the compute savings. GPU acceleration is strictly an optimization for **high-density** data processing.13  
* **Asynchronous Streams:** LiveView must manage these offloaded tasks asynchronously (using Task.async or Nx async streams) to prevent blocking the socket process, which would result in heartbeat timeouts and client disconnections.14

### **2.3 Rasterization Strategies: Image and Evision**

One architectural pattern for high-density visualization is **Server-Side Rasterization**. Instead of sending data points, the server renders a PNG or JPEG and sends the image.

**The Stack:**

1. **Nx Tensor:** Holds the raw data (e.g., a 2D matrix of temperature values).  
2. **Heatmap Generation:** Nx.to\_heatmap/2 or manual color mapping converts the data tensor into a (Height, Width, 3\) tensor representing RGB pixels.15  
3. **Image Encoding:** The **Image** library (wrapping libvips) or **Evision** (wrapping OpenCV) takes this tensor and encodes it into a standard format like PNG.17  
4. **Transport:** The binary image data is Base64 encoded (adding 33% size overhead) or sent via a binary channel to the client.

Constraint 5: Encoding Latency.  
While libvips is incredibly fast, encoding a 4K image at 60Hz is CPU-prohibitive. This architecture is best suited for complex visualizations where the visual complexity (millions of points) is high, but the update frequency is low (e.g., updating a weather radar map every 5 minutes).9

## **3\. The Transport Layer: Breaking the JSON Barrier**

Data must travel from the server to the client. The default transport mechanism in Phoenix LiveView is push\_event, which serializes the payload to JSON.20

### **3.1 The Serialization Tax**

JSON is text-based. A single 32-bit float like 0.123456789 occupies 4 bytes in memory but 11 bytes as a string.

* **Expansion Factor:** Data size expands by roughly 2.5x to 3x when serialized to JSON.  
* **CPU Cost:** The Jason library in Elixir is optimized, but encoding massive lists consumes reductions (scheduler time). More critically, on the client side, the browser's JSON.parse() must run on the main thread, blocking rendering and user interaction.21

### **3.2 Binary Data Optimization and "Upload" Hacks**

To achieve high-performance plotting, one must bypass JSON.

Mechanism 1: The Upload Channel Hack  
A creative use of LiveView's allow\_upload mechanism can create a dedicated binary channel. By treating the data stream as a "file upload" in reverse (or utilizing the underlying binary framing of the upload socket), developers can stream raw binaries efficiently. This utilizes the Phoenix.Socket binary frame capability, avoiding text encoding overhead entirely.22  
Mechanism 2: Custom Binary Channels  
Developers can instantiate a separate Phoenix.Channel alongside the LiveView socket. This channel can be configured to use a binary serializer.

* **Server:** Nx.to\_binary/1 extracts the raw byte sequence from a tensor.  
* **Wire:** The raw bytes are sent.  
* **Client:** The browser receives an ArrayBuffer.  
* **Zero-Copy:** The JavaScript code can create a Float32Array view directly on top of this ArrayBuffer. This is a zero-copy operation (in terms of parsing), instant and memory-efficient.20

## **4\. Client-Side Rendering (CSR): The Visualization Engine**

When data is delivered efficiently to the client, it must be rendered. The choice of client-side technology is the final determinant of performance.

### **4.1 The Hook Ecosystem**

LiveView Hooks (phx-hook) are the bridge between the declarative server state and the imperative client DOM.25

**Lifecycle Management:**

* **mounted()**: The critical initialization phase. Here, the charting library (e.g., uPlot, Chart.js) is instantiated. It is imperative to set phx-update="ignore" on the container element. If this attribute is missing, the next LiveView diff will wipe out the Canvas element and the chart instance, causing a flicker or state loss.26  
* **handleEvent()**: The Hook listens for events pushed from the server. This is where the data payload arrives.  
* **pushEvent()**: The Hook sends interaction data (zoom levels, cursor position) back to the server.

### **4.2 Library Analysis: Canvas vs. WebGL**

**HTML5 Canvas (2D Context):**

* **Libraries:** **uPlot**, **Chart.js**.  
* **Performance:** Canvas is a raster bitmap. It is significantly faster than SVG for high object counts because it does not maintain a scene graph.  
* **The uPlot Advantage:** uPlot is specifically designed for high-performance time-series. It expects "flat" arrays (Structure of Arrays) rather than arrays of objects (Array of Structures). This aligns perfectly with the column-oriented data structures often used in Nx/Explorer and minimizes JavaScript garbage collection. It can render \~150,000 points in under 50ms.28

**WebGL (3D Context):**

* **Libraries:** **Regl**, **WebGL-Plot**, **Three.js**.  
* **Performance:** WebGL grants direct access to the GPU shader pipeline. It allows rendering millions of points by uploading data to GPU buffers (VBOs).  
* **Constraint:** Complexity. WebGL requires managing context loss, shader compilation, and buffer allocation. It is overkill for simple line charts but essential for massive scatter plots or 3D surface visualizations.30

### **4.3 The WebAssembly (WASM) Frontier**

WASM offers a way to run compiled code (C, Rust, Zig) in the browser at near-native speeds.

Rust \+ Plotters (WASM):  
The Plotters library in Rust can compile to WASM and render to an HTML5 Canvas.

* **Pros:** Algorithm sharing. The same Rust code used to generate a static PNG on the server (via Rustler) can be used to render an interactive chart on the client (via WASM).31  
* **Cons:** The "Bridge" Tax. Calling into WASM from JavaScript requires marshalling data into the WASM linear memory. For simple rendering loops, this copying overhead can sometimes exceed the performance gains, making highly optimized JS libraries like uPlot faster for specific use cases. WASM shines when the *computation* per data point is high (e.g., real-time signal filtering on the client) before rendering.32

## **5\. Architectural Integration Patterns**

Based on the analysis of these constraints, we can identify three distinct architectural patterns for data visualization in Phoenix LiveView.

### **Pattern A: The "Thin Server" (Client-Heavy)**

* **Mechanism:** The server queries the database or receives telemetry. It performs minimal processing (perhaps simple filtering). Data is serialized to binary (via Nx.to\_binary or custom packing) and pushed to the client.  
* **Client:** A LiveView Hook receives the ArrayBuffer, wraps it in a Typed Array, and passes it to **uPlot** or **ECharts**.  
* **Use Case:** Real-time stock tickers, server metric dashboards, IoT sensor feeds.  
* **Rationale:** Minimizes server CPU load. Maximizes interactivity (zooming/panning is handled locally by JS).  
* **Constraint:** Initial load size. If the dataset is 100MB, the initial page load will be slow.

### **Pattern B: The "Thick Server" (Server-Side Rasterization)**

* **Mechanism:** The server uses **Nx** and **Evision/Image** to render a visualization into a static image (PNG/JPEG). This image is sent to the client as a Base64 string or a temporary URL.  
* **Client:** A simple \<img\> tag.  
* **Use Case:** Complex heatmaps, contour plots, scientific imaging, or scenarios where the client device is extremely low-power (e.g., embedded kiosks).  
* **Rationale:** Guarantees consistent rendering regardless of client hardware. Leveraging Server GPUs (EXLA).  
* **Constraint:** Bandwidth heavy. High latency for interactions.

### **Pattern C: The "Hybrid Window" (Downsampling)**

* **Mechanism:** The server holds the massive dataset (e.g., 10 years of data, 1 billion points). It accepts a "viewport" parameter from the client (start time, end time). It uses the **LTTB** (Largest-Triangle-Three-Buckets) algorithm (implemented in Rust via Rustler or optimized Nx) to downsample the data to a visual resolution (e.g., 1000 points) that preserves the visual shape. These 1000 points are sent to the client.  
* **Client:** Renders the 1000 points. When the user zooms, a pushEvent requests a new set of downsampled points for the new window.  
* **Use Case:** Historical data analysis, banking ledgers, seismic activity logs.  
* **Rationale:** The only scalable way to visualize datasets larger than client memory.

## **6\. Detailed Technology Analysis: Libraries and Tools**

### **6.1 Tucan and Vega-Lite**

**Tucan** is an Elixir wrapper around **Vega-Lite**.

* **Mechanism:** Tucan generates a JSON specification of the chart. This JSON is sent to the client, where the Vega-Lite JavaScript library parses it and renders the chart (usually to Canvas or SVG).  
* **Pros:** Declarative, grammar of graphics, highly expressive.  
* **Cons:** The "Spec" overhead. For every update, the JSON spec might need regeneration and re-parsing. While better than raw SVG DOM diffing, it is slower than updating raw data arrays in uPlot.34

### **6.2 Rustler: The Native Bridge**

**Rustler** allows writing "Safe" NIFs in Rust.

* **Safety:** Unlike C NIFs, which can crash the entire BEAM VM if they segfault, Rust's memory safety guarantees protect the server.  
* **Dirty Schedulers:** CPU-intensive plotting algorithms (like generating a fractal or processing a large image) should be flagged as DirtyCpu or DirtyIo. This tells the BEAM to run them on a separate thread pool, preventing them from blocking the lightweight process schedulers that handle LiveView connections.35

### **6.3 Plotting Library Feature Matrix**

| Library | Rendering | Backend | Data Capacity | Best for LiveView? |
| :---- | :---- | :---- | :---- | :---- |
| **Contex** | SVG | Elixir (SSR) | Low (\< 1k) | Reporting / Simple Dashboards |
| **Matplotex** | SVG/Image | Elixir/Nx | Med (\< 10k) | Scientific Static Plots |
| **Tucan** | Canvas/SVG | Vega-Lite (CSR) | Med (\< 50k) | Declarative / Grammar of Graphics |
| **Chart.js** | Canvas | JS (CSR) | Med (\< 50k) | General Purpose / Easy API |
| **uPlot** | Canvas | JS (CSR) | High (\< 1M) | **High-Frequency Time Series** |
| **Webgl-plot** | WebGL | JS (CSR) | Massive (\> 1M) | Oscilloscopes / raw data streams |
| **Plotters** | Canvas/Img | Rust (WASM/SSR) | High | Shared Logic / Complex Rendering |

## **7\. Comparative Performance Analysis (Data Transport)**

The choice of data transport serialization profoundly impacts the "Time to Visual" metric.

### **Table 1: Serialization Overhead for 100,000 Float32 Points**

| Format | Size on Wire (approx) | Server CPU Cost | Client CPU Cost | Notes |
| :---- | :---- | :---- | :---- | :---- |
| **JSON** | \~1.1 MB | High (Encoding) | High (Parsing) | Default push\_event. Blocks main thread. |
| **Base64** | \~533 KB | Medium (Encoding) | Medium (Decoding) | Necessary for binary via JSON. |
| **Raw Binary** | 400 KB | **Low (Memcpy)** | **Zero (View)** | Requires Typed Arrays & ArrayBuffer. |
| **ETF** | \~400 KB \+ overhead | Medium | High (Parsing) | Erlang Term Format. Requires JS parser. |

**Insight:** Raw binary transfer is the only viable option for high-frequency updates (e.g., 60Hz) of large datasets. It minimizes the payload to the theoretical minimum (4 bytes per float) and eliminates parsing overhead on the client, allowing the JavaScript engine to hand the memory buffer directly to the Canvas or WebGL context.

## **8\. Conclusion and Future Outlook**

The constraints of plotting in Elixir Phoenix LiveView are not limitations of the language, but rather the physical realities of distributed systems and browser architectures. The "naive" LiveView approach—relying solely on server-rendered HTML diffs—encounters a hard ceiling defined by DOM manipulation costs and JSON serialization latencies.

However, the Elixir ecosystem provides a powerful set of tools to transcend these limits. By treating the server as a high-performance computation engine (via **Nx** and **Rustler**) and the client as a dedicated rendering terminal (via **Hooks**, **Canvas**, and **Binary Channels**), developers can achieve performance parity with, or even exceed, traditional Single Page Applications.

**Key Takeaways:**

1. **Abandon SVG** for real-time data. Use Canvas (uPlot) or WebGL.  
2. **Bypass JSON.** Utilize binary transport for data payloads.  
3. **Leverage Nx.** Use tensors for efficient memory layout and "zero-copy" binary extraction.  
4. **Embrace Hybrid Architectures.** Perform heavy lifting (downsampling, aggregation) on the server (Rust/Nx) and light rendering on the client.

As WebAssembly integration matures and LiveView introduces native support for binary streams and typed array interactions, the friction between the server and the GPU will further decrease, solidifying Elixir's position as a premier stack for data-intensive, real-time applications.

### **Citations**

31

## ---

**Section 1: The Theoretical Framework of Real-Time Functional UIs**

The intersection of functional programming and real-time user interfaces creates a unique set of architectural tensions. To understand the constraints of plotting in Phoenix LiveView, one must first deconstruct the underlying theoretical models: the Actor Model of the BEAM and the Event Loop of the browser.

### **1.1 The Actor Model vs. The Event Loop**

Elixir applications run on the BEAM (Erlang Virtual Machine), which implements the Actor Model. In this model, a "process" is a lightweight, isolated thread of execution with its own memory heap. A Phoenix LiveView is simply a process. It holds state (the socket.assigns) and reacts to messages (events). This architecture provides incredible concurrency; a single server can handle hundreds of thousands of connected clients, each with its own isolated state.1

In contrast, the browser runs on a single-threaded Event Loop. All JavaScript execution, DOM manipulation, and layout calculation happen on this single thread. If a script takes too long to execute (e.g., parsing a massive JSON object or calculating layout for 10,000 SVG nodes), the UI freezes. This is "jank."

The Synchronization Gap:  
The challenge in LiveView plotting is synchronizing these two disparate models over a network gap.

* **The Server (Actor)** wants to emit state changes as fast as data arrives (e.g., 100 times per second for a vibration sensor).  
* **The Client (Event Loop)** is constrained by the refresh rate of the display (typically 60Hz or roughly 16ms per frame).  
* **The Constraint:** If the server pushes updates faster than the network can transmit or the client can render, we create "backpressure." In a naive LiveView implementation, messages pile up in the process mailbox or the WebSocket buffer, leading to memory bloat and latency spikes. Efficient plotting requires flow control—throttling or conflating updates on the server to match the client's consumption rate.14

### **1.2 The Physics of Latency: Bandwidth-Delay Product**

Network constraints are physical. The Bandwidth-Delay Product (BDP) defines the amount of data "in flight" on the network.

$$BDP \= Bandwidth \\times RTT$$

For a visualization application, this dictates the responsiveness.  
If a user interacts with a chart (e.g., zooming in), and that interaction logic lives on the server, the signal must travel the RTT.

* **Fiber Connection:** 20ms RTT. The lag is imperceptible.  
* **4G/LTE:** 100ms-300ms RTT. The lag is noticeable; the UI feels "sticky."  
* **Satellite:** 600ms+ RTT. The UI is broken.

The "Uncanny Valley" of Server-Driven UI:  
LiveView enables "Server-Driven UI." This is excellent for forms and navigation. However, for direct manipulation interfaces like charts, it creates an "Uncanny Valley" effect. The visual fidelity (high-resolution charts) promises a native-app experience, but the interaction latency breaks the illusion.

* **Mitigation:** We must decouple **data** from **interaction**. The data can stream from the server (accepting latency), but the interaction (zooming, panning, tooltips) *must* be handled client-side in the JavaScript Event Loop to maintain the 60fps illusion of responsiveness. This necessitates the use of LiveView Hooks to bridge the gap.25

### **1.3 Evolution of Web Plotting: Context**

To appreciate the current constraints, we must view them in historical context.

1. **Server-Side Image Generation (1990s-2000s):** Tools like RRDTool generated static PNGs. Simple, zero client CPU usage, but zero interactivity. (This is analogous to the Nx/Matplotex approach today).  
2. **Client-Side SVG (2010s):** D3.js revolutionized the web by binding data to DOM elements. It allowed interactivity but hit performance walls at high object counts. (Analogous to Contex in LiveView).  
3. **Canvas & WebGL (2015-Present):** Libraries like Chart.js and Three.js moved to rasterization on the client, sacrificing the DOM's convenience for raw speed.  
4. **The LiveView Era (2019+):** We are attempting to get the best of all worlds—server-side state management (like RRDTool) with client-side interactivity (like D3/Canvas). The constraint is the "glue" layer—how efficiently we can tunnel data through the WebSocket to feed the Canvas engine.

## **2\. The Server-Side Compute Engine (The "Brain")**

The server in a LiveView plotting architecture is not just a database fetcher; it is a computational engine. The introduction of **Nx** has provided Elixir with the primitives to perform high-performance numerical work that was previously delegated to Python or C++.

### **2.1 Nx Architecture: Tensors as Binaries**

The foundational constraint of doing math in Erlang/Elixir was the memory model. A list of numbers \[1.0, 2.0, 3.0\] is a linked list.

* **Overhead:** Each element is a "cons cell" containing a value and a pointer to the next cell.  
* **Cache Locality:** Elements are scattered across the heap. Iterating through a list guarantees CPU cache misses.

The Nx Solution:  
Nx introduces Tensors. Under the hood, an Nx tensor is a struct wrapping a Binary. In the BEAM, a binary is a contiguous sequence of bytes.

* **Memory Density:** A binary \<\<0, 0, 128, 63,...\>\> stores 32-bit floats packed tightly. There are no pointers. The CPU can load these bytes into SIMD registers and process them in parallel.9  
* **Creation Costs:** Understanding Nx.tensor vs. Nx.from\_binary is critical.  
  * Nx.tensor(\[1, 2,...\]): Iterates the list (slow) and builds the binary. $O(N)$ with high constant factors.  
  * Nx.from\_binary(\<\<...\>\>, type): Wraps the existing binary in a struct. $O(1)$. This is crucial when loading data from files, network sockets, or databases.50

Endianness:  
When interpreting raw binaries, one must be aware of the CPU's endianness (byte order). Nx handles this, but when manually constructing binaries to send to a client (which might be Little Endian while the server is Big Endian, though rare now as x86/ARM are Little Endian), explicit handling via native modifiers in Elixir binaries \<\<val :: little-float-32\>\> is required to ensure the client reads the correct values.9

### **2.2 The GPU Bottleneck: PCI-E and Latency**

Nx supports pluggable backends. **EXLA** (Elixir XLA) interfaces with Google's XLA (Accelerated Linear Algebra) compiler to run computations on the GPU.

When to use GPU:  
Using a GPU for plotting sounds appealing, but it introduces the PCI-Express (PCI-E) Transfer Bottleneck.

* **Scenario:** You have a 100x100 matrix and want to normalize it.  
  * **CPU:** The data is in L3 cache. Operation takes 10 microseconds.  
  * **GPU:** The driver must allocate VRAM, copy data over PCI-E (latency \~20-100 microseconds), launch the kernel, and copy results back.  
  * **Result:** The GPU is slower due to transport overhead.  
* **Optimization:** GPU acceleration is only viable when the *arithmetic intensity* (calculations per byte of memory transfer) is high. For example, calculating a Mandelbrot set or performing a convolution on a 4K image. For standard time-series normalization, the CPU (Binary backend) is often faster and strictly simpler.13

### **2.3 Evision and Image: The Rasterization Path**

Sometimes, the best way to plot a million points is to not send them at all. **Server-Side Rasterization** involves generating a pixel image on the server.

Evision (OpenCV):  
Evision provides NIF bindings to OpenCV. It enables advanced computer vision tasks but also robust plotting capabilities.

* **Constraint:** NIF safety. A crashing NIF crashes the BEAM. Evision manages this well, but heavy operations should use Dirty Schedulers.  
* **Nx Integration:** Evision.Nx.to\_mat/1 converts an Nx tensor to an OpenCV Matrix. This allows you to do math in Nx and rendering in OpenCV.18

Image (libvips):  
The Image library is based on libvips, a demand-driven, streaming image processing library. It is extremely memory efficient compared to ImageMagick.

* **Nx Integration:** Image.from\_nx/1 creates an image from a tensor. This is useful for generating heatmaps. You can define a tensor of values, map them to colors, convert to an image, and encode as PNG.17  
* **Performance:** libvips avoids loading the whole image into memory if possible, but from\_nx forces the materialization of the tensor. The conversion involves a memory copy from the BEAM binary to the libvips memory space. While optimized, this copy is a constraint for 60fps throughput.53

### **2.4 Plotting Libraries: The Feature Matrix**

Selecting the right library is a trade-off between features and performance.

#### **Contex (SVG)**

* **Mechanism:** Generates SVG strings.  
* **Constraint:** DOM weight. Good for static, print-quality charts. Bad for real-time.  
* **Snippet Insight:** "There's no state management in the chart generation... no smarts to send incremental diffs".6 This confirms that Contex re-sends the whole chart on updates, exacerbating the bandwidth problem.

#### **Matplotex**

* **Mechanism:** Mimics Matplotlib syntax. Uses Nx backends.  
* **Constraint:** Primarily targets static image generation (SVG/PNG) for reports or embedded systems (Nerves) where a display might be directly attached, rather than web interactive plotting.38

#### **Tucan (Vega-Lite)**

* **Mechanism:** Generates a **Vega-Lite JSON specification**.  
* **Optimization:** This acts as a compression layer. Instead of sending "draw a line from 0,0 to 10,10...", you send a high-level spec: "Draw a line chart of this data." The client-side Vega library expands this into rendering instructions.  
* **Constraint:** The *Data* is still embedded in the JSON spec (or linked via URL). If the data is massive, the JSON payload is still the bottleneck.34

## **3\. The Transport Layer (The "Nervous System")**

The most critical bottleneck in LiveView plotting is the connection between the server and the browser.

### **3.1 Serialization: The JSON Tax**

By default, push\_event encodes payloads as JSON.

* **Constraint:** JSON is inefficient for numbers. A list of 10,000 integers \[12345, 12346,...\] becomes a string "\[12345,12346,...\]".  
* **CPU Cost:** The Jason encoder on the server must traverse the list. The browser must parse the string. This parsing happens on the UI thread, causing jank.21

### **3.2 Binary Data Optimization**

To achieve "native" performance, we must use **Binary** transport.

The "Upload Channel" Hack:  
Before official binary support, developers used LiveView's allow\_upload feature.

* **Mechanism:** The upload architecture establishes a binary channel for file data. Developers could hijack this to send visualization data "down" to the client, or use it to stream data "up" efficiently.  
* **Constraint:** It's complex to set up for this unintended use case.

Raw Binary via push\_event (The Modern Way):  
Modern LiveView versions support binary payloads more gracefully, or one can use a dedicated Phoenix.Channel.

* **Technique:** Use Nx.to\_binary/1 to get the raw byte blob. Send this blob.  
* **Base64 Constraint:** If the channel expects text (JSON), you must Base64 encode the binary. This adds 33% overhead size and requires atob() decoding on the client.  
* **Solution:** Use a channel configured for binary frames. The browser receives an ArrayBuffer.  
  JavaScript  
  // Client Side  
  channel.on("data", payload \=\> {  
    // payload is ArrayBuffer  
    const floatView \= new Float32Array(payload);  
    uPlot.setData(\[floatView\]);  
  });

  This is the **Holy Grail** of transport: Zero-copy parsing. The binary data from the server's memory is dumped directly into the client's memory.20

### **3.3 Compression Strategies**

Is Gzip/Brotli useful?

* **Text (JSON/SVG):** Yes, massive reduction (90%).  
* **Binary (Floats):** No. Floating point numbers have high entropy (randomness in the mantissa). Compressing a packed float array often yields negligible gains and burns CPU cycles on both ends.  
* **Recommendation:** Do not compress raw binary float streams unless the data has high redundancy (e.g., lots of zeros).54

## **4\. Client-Side Rendering (The "Face")**

Once data arrives, the browser must draw it.

### **4.1 DOM vs. Canvas vs. WebGL**

**The DOM (SVG):**

* **Mechanism:** Retained Mode. You tell the browser "there is a circle here," and it remembers.  
* **Constraint:** Memory per node. 10,000 circles \= 10,000 objects. Slow hit testing.

**Canvas (2D):**

* **Mechanism:** Immediate Mode. You tell the browser "paint a red pixel here." It forgets immediately.  
* **Constraint:** You must redraw the *entire* scene for every frame (usually). However, blitting pixels is extremely fast.  
* **Capacity:** Can handle \~100k \- 500k points at 60fps.28

**WebGL (3D):**

* **Mechanism:** Parallel processing on the GPU.  
* **Constraint:** Data transfer to GPU (VBOs). Shader complexity.  
* **Capacity:** Millions of points.

### **4.2 The Case for uPlot**

**uPlot** stands out as the optimal partner for LiveView.28

* **Architecture:** It uses **Typed Arrays** internally. This aligns perfectly with the ArrayBuffer received from a binary LiveView channel.  
* **Memory:** It avoids creating JavaScript objects for data points. Most chart libraries create {x: 1, y: 2} objects. uPlot uses \[x\_array, y\_array\]. This minimizes Garbage Collection (GC) pauses, which are the main cause of "stutter" in JS animations.  
* **Integration:** A LiveView Hook can initialize uPlot. When binary data arrives, it creates a view on the buffer and calls uPlot.setData(). This pipeline is lean enough to sustain 60Hz updates.

### **4.3 LiveView Hooks Mechanics**

The phx-hook is the interoperability layer.

* **phx-update="ignore":** This is the most critical attribute. It tells LiveView "I have given this DOM node to JavaScript (uPlot); do not touch it." If you forget this, LiveView's diffing engine will reset the container on every update, destroying the chart.27  
* **Optimistic UI:** When a user zooms, if you wait for the server to confirm the new range, it feels laggy. The Hook should immediately update the chart scale (Optimistic Update) and *then* inform the server via pushEvent. If the server rejects it, the Hook rolls back.

## **5\. The WebAssembly (WASM) Frontier (The "Prosthetic")**

WASM is often touted as the performance savior. In the context of plotting, the reality is nuanced.

### **5.1 Rust and Plotters**

**Plotters** is a Rust library that can render to bitmaps, SVG, or HTML5 Canvas via WASM.31

* **Consistency:** You can use the exact same Rust code to generate a PNG on the server (for email reports) and render to Canvas on the client.  
* **WASM Performance:** For *rendering* (issuing draw calls), WASM is often *slower* than JavaScript. Why? Because the Canvas API is part of the browser (C++). JavaScript calls it directly. WASM must call through a "trampoline" (JS glue code) to reach the Canvas API. This adds overhead.  
* **WASM Win:** WASM wins when you have heavy *computation* before rendering. Example: Calculating a Moving Average Convergence Divergence (MACD) on 1 million points. Rust/WASM will crunch the numbers 10x faster than JS.  
* **Constraint:** Marshalling. Moving the 1 million points from JS (WebSocket) into the WASM memory space involves a copy. This copy can negate the compute savings for trivial plots.32

### **5.2 Integration Pattern: Rustler \+ WASM**

A powerful pattern is **Shared Logic**.

* **Common Library:** Write the data processing logic in a Rust crate.  
* **Server:** Use **Rustler** to bind this crate to Elixir. This allows the server to perform heavy aggregations efficiently using Dirty Schedulers.35  
* **Client:** Compile the same crate to WASM. The client can perform the same aggregations for "offline" interaction or immediate feedback.

## **6\. Architectural Patterns & Case Studies**

We can condense these constraints into recommended architectures for specific scenarios.

### **Scenario A: The IoT Ticker (High Frequency, Moving Window)**

* **Constraint:** 60 updates/sec. New data pushes old data out.  
* **Solution:** **Binary Transport \+ uPlot.**  
* **Server:** Maintains a ring buffer. Pushes raw binary chunks of *new* data only.  
* **Client (Hook):** Appends data to uPlot's buffer. uPlot handles the scrolling efficiently.  
* **Avoid:** SVG (DOM thrashing), JSON (GC pauses).

### **Scenario B: The Seismic Analyzer (Massive Static Dataset)**

* **Constraint:** 10GB dataset. User needs to zoom in to see details.  
* **Solution:** **Server-Side Downsampling (Hybrid).**  
* **Server:** Holds full data in Nx/Disk. Implements **LTTB** downsampling algorithm.  
* **Interaction:** Client sends zoom(start, end). Server selects data in that range, downsamples to 1000 points, sends result.  
* **Rationale:** Sending 10GB to client is impossible. Sending an image (Rasterization) prevents client-side hovering/inspection. Downsampling preserves the "shape" while reducing cardinality to what the screen can actually display (pixels are finite).

### **Scenario C: The Heatmap (Complex 2D/3D Data)**

* **Constraint:** Rendering requires complex interpolation/shaders.  
* **Solution:** **Server-Side Rasterization (Nx \+ Image).**  
* **Server:** Computes heatmap on GPU (EXLA). Renders to PNG.  
* **Client:** Receives Base64 image.  
* **Rationale:** Implementing complex heatmap interpolation in JS/Canvas is slow and error-prone. The visual output is static enough that image transfer bandwidth is acceptable.

## **7\. Comparison Tables**

### **Table 1: Rendering Approaches Comparison**

| Approach | Rendering Engine | Data Capacity (approx.) | Latency Impact | Best Use Case |
| :---- | :---- | :---- | :---- | :---- |
| **SSR (Contex)** | SVG (DOM) | \< 1,000 points | High (Serialization/Diffing) | Reporting, Simple Dashboards |
| **SSR (Raster)** | Image (Pixels) | Unlimited (Server-side) | Med (Transfer size) | Heatmaps, Scientific Imaging |
| **CSR (Chart.js)** | Canvas (Objects) | \< 10,000 points | Low (Client rendering) | General purpose, Low density |
| **CSR (uPlot)** | Canvas (Typed Arrays) | \~1,000,000 points | Very Low | **High-Frequency Time Series** |
| **CSR (WebGL)** | GPU Shaders | \> 1,000,000 points | Low | Massive Scatterplots |

### **Table 2: Transport Efficiency (100k Floats)**

| Format | Size (KB) | Server CPU | Client CPU | Note |
| :---- | :---- | :---- | :---- | :---- |
| **JSON** | \~1,100 | High | High | Default. Avoid for plotting. |
| **Base64** | \~533 | Medium | Medium | Necessary if binary channel unavailable. |
| **Raw Binary** | **400** | **Low** | **Zero** | **Optimal.** Zero-copy parsing. |

## **8\. Conclusion**

High-performance plotting in Phoenix LiveView is a solved problem, but it requires deviating from the "pure" LiveView philosophy of "Server Renders HTML." The constraints of the DOM and JSON serialization are physical barriers that cannot be optimized away.

Success lies in a **Hybrid Architecture**:

1. **Server (Elixir/Nx/Rust):** Acts as the high-performance Compute and Orchestration engine. It holds the "Truth." It prepares data using binary-efficient structures.  
2. **Transport:** Utilizes dedicated binary channels to bypass JSON overhead.  
3. **Client (Hooks/Canvas/WASM):** Acts as a dumb, efficient rendering terminal. It acknowledges that the browser's Event Loop is the only place where 60fps interactivity can be guaranteed.

By respecting the bandwidth-delay product and the memory layout of modern hardware, developers can build Elixir applications that visualize millions of data points with the responsiveness of a native desktop application.

#### **Works cited**

1. Here's How Phoenix LiveView is Redefining Scalable Interfaces, accessed December 13, 2025, [https://hexshift.medium.com/heres-how-phoenix-liveview-is-redefining-scalable-interfaces-fe7c7c9b1649](https://hexshift.medium.com/heres-how-phoenix-liveview-is-redefining-scalable-interfaces-fe7c7c9b1649)  
2. Contex \- a pure Elixir server-side charting library generating SVG ..., accessed December 13, 2025, [https://elixirforum.com/t/contex-a-pure-elixir-server-side-charting-library-generating-svg-output/28582?page=3](https://elixirforum.com/t/contex-a-pure-elixir-server-side-charting-library-generating-svg-output/28582?page=3)  
3. a pure Elixir server-side charting library generating SVG output, accessed December 13, 2025, [https://elixirforum.com/t/contex-a-pure-elixir-server-side-charting-library-generating-svg-output/28582](https://elixirforum.com/t/contex-a-pure-elixir-server-side-charting-library-generating-svg-output/28582)  
4. latency and rendering optimizations in Phoenix LiveView \- Dashbit, accessed December 13, 2025, [https://dashbit.co/blog/latency-rendering-liveview](https://dashbit.co/blog/latency-rendering-liveview)  
5. Real-Time SVG Charts with Contex and LiveView | Blog \- Elixir School, accessed December 13, 2025, [https://elixirschool.com/blog/server-side-svg-charts-with-contex-and-liveview](https://elixirschool.com/blog/server-side-svg-charts-with-contex-and-liveview)  
6. FAQ \- ContEx Charts, accessed December 13, 2025, [https://contex-charts.org/faq](https://contex-charts.org/faq)  
7. Tensors and Nx, are not just for machine learning \- Fly.io, accessed December 13, 2025, [https://fly.io/phoenix-files/tensors-and-nx-are-not-just-for-machine-learning/](https://fly.io/phoenix-files/tensors-and-nx-are-not-just-for-machine-learning/)  
8. Nx for Absolute Beginners \- DockYard, accessed December 13, 2025, [https://dockyard.com/blog/2022/03/15/nx-for-absolute-beginners](https://dockyard.com/blog/2022/03/15/nx-for-absolute-beginners)  
9. Thinking in Tensors \- The Pragmatic Programmers \- Medium, accessed December 13, 2025, [https://medium.com/pragmatic-programmers/thinking-in-tensors-687e2a42512](https://medium.com/pragmatic-programmers/thinking-in-tensors-687e2a42512)  
10. Nx (Numerical Elixir) is now publicly available \- Dashbit Blog, accessed December 13, 2025, [https://dashbit.co/blog/nx-numerical-elixir-is-now-publicly-available](https://dashbit.co/blog/nx-numerical-elixir-is-now-publicly-available)  
11. Three Years of Nx: Growing the Elixir Machine Learning Ecosystem, accessed December 13, 2025, [https://dockyard.com/blog/2023/11/08/three-years-of-nx-growing-the-machine-learning-ecosystem](https://dockyard.com/blog/2023/11/08/three-years-of-nx-growing-the-machine-learning-ecosystem)  
12. Interactive coding notebooks with Elixir, Nx and Livebook. \- b-nova, accessed December 13, 2025, [https://b-nova.com/en/home/content/powerful-interactive-numerical-computing-notebooks-with-elixir-nx-and-livebook/](https://b-nova.com/en/home/content/powerful-interactive-numerical-computing-notebooks-with-elixir-nx-and-livebook/)  
13. Mapping slices of an Nx tensor \- elixir \- Stack Overflow, accessed December 13, 2025, [https://stackoverflow.com/questions/75962824/mapping-slices-of-an-nx-tensor](https://stackoverflow.com/questions/75962824/mapping-slices-of-an-nx-tensor)  
14. Top Ten Ways to Boost Performance in Phoenix LiveView \- Hex Shift, accessed December 13, 2025, [https://hexshift.medium.com/top-ten-ways-to-boost-performance-in-phoenix-liveview-5cfdb3c35547](https://hexshift.medium.com/top-ten-ways-to-boost-performance-in-phoenix-liveview-5cfdb3c35547)  
15. Examples — NxImage v0.1.2 \- Hexdocs, accessed December 13, 2025, [https://hexdocs.pm/nx\_image/examples.html](https://hexdocs.pm/nx_image/examples.html)  
16. Recognize digits using ML in Elixir · The Phoenix Files \- Fly.io, accessed December 13, 2025, [https://fly.io/phoenix-files/recognize-digits-using-ml-in-elixir/](https://fly.io/phoenix-files/recognize-digits-using-ml-in-elixir/)  
17. Image — image v0.62.1 \- Hexdocs, accessed December 13, 2025, [https://hexdocs.pm/image/Image.html](https://hexdocs.pm/image/Image.html)  
18. cocoa-xu/evision \- An OpenCV-Erlang/Elixir binding \- GitHub, accessed December 13, 2025, [https://github.com/cocoa-xu/evision](https://github.com/cocoa-xu/evision)  
19. elixir-image/image: Image processing for Elixir \- GitHub, accessed December 13, 2025, [https://github.com/elixir-image/image](https://github.com/elixir-image/image)  
20. Network optimization (4x WS message size reduction) for sending ..., accessed December 13, 2025, [https://dev.to/azyzz/network-optimization-for-sending-lot-of-data-from-liveview-to-client-using-pushevent-2nl](https://dev.to/azyzz/network-optimization-for-sending-lot-of-data-from-liveview-to-client-using-pushevent-2nl)  
21. zookzook/binary\_ws: Phoenix live view \+ binary websocket \- GitHub, accessed December 13, 2025, [https://github.com/zookzook/binary\_ws](https://github.com/zookzook/binary_ws)  
22. Streaming Uploads with LiveView · The Phoenix Files \- Fly.io, accessed December 13, 2025, [https://fly.io/phoenix-files/streaming-uploads-with-liveview/](https://fly.io/phoenix-files/streaming-uploads-with-liveview/)  
23. Phoenix LiveView v1.1.18 \- Hexdocs, accessed December 13, 2025, [https://hexdocs.pm/phoenix\_live\_view/Phoenix.LiveView.html](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)  
24. PhoenixLiveView push\_event with binary payload \- Elixir Forum, accessed December 13, 2025, [https://elixirforum.com/t/phoenixliveview-push-event-with-binary-payload/44242](https://elixirforum.com/t/phoenixliveview-push-event-with-binary-payload/44242)  
25. Implementing a Client Hook in LiveView \- DockYard, accessed December 13, 2025, [https://dockyard.com/blog/2025/03/11/implementing-a-client-hook-in-liveview](https://dockyard.com/blog/2025/03/11/implementing-a-client-hook-in-liveview)  
26. Installation of the uPlot with Phoenix 1.6.6 and Phoenix live view ..., accessed December 13, 2025, [https://elixirforum.com/t/installation-of-the-uplot-with-phoenix-1-6-6-and-phoenix-live-view-0-17-5/47570](https://elixirforum.com/t/installation-of-the-uplot-with-phoenix-1-6-6-and-phoenix-live-view-0-17-5/47570)  
27. Phoenix LiveView JavaScript Hooks and Select2 \- Poeticoding, accessed December 13, 2025, [https://www.poeticoding.com/phoenix-liveview-javascript-hooks-and-select2/](https://www.poeticoding.com/phoenix-liveview-javascript-hooks-and-select2/)  
28. leeoniya/uPlot: A small, fast chart for time series, lines, areas, ohlc ..., accessed December 13, 2025, [https://github.com/leeoniya/uPlot](https://github.com/leeoniya/uPlot)  
29. Show HN: Plotting 3 years of hourly data in 150ms \- Hacker News, accessed December 13, 2025, [https://news.ycombinator.com/item?id=23045207](https://news.ycombinator.com/item?id=23045207)  
30. danchitnis/webgl-plot: A high-Performance real-time 2D ... \- GitHub, accessed December 13, 2025, [https://github.com/danchitnis/webgl-plot](https://github.com/danchitnis/webgl-plot)  
31. plotters-rs/plotters: A rust drawing library for high quality data plotting ..., accessed December 13, 2025, [https://github.com/plotters-rs/plotters](https://github.com/plotters-rs/plotters)  
32. A Real-World Benchmark of WebAssembly vs. ES6 | by Aaron Turner, accessed December 13, 2025, [https://medium.com/@torch2424/webassembly-is-fast-a-real-world-benchmark-of-webassembly-vs-es6-d85a23f8e193](https://medium.com/@torch2424/webassembly-is-fast-a-real-world-benchmark-of-webassembly-vs-es6-d85a23f8e193)  
33. Will WebAssembly Kill JavaScript? Let's Find Out (+ Live Demo), accessed December 13, 2025, [https://dev.to/sylwia-lask/will-webassembly-kill-javascript-lets-find-out-live-demo-43ln](https://dev.to/sylwia-lask/will-webassembly-kill-javascript-lets-find-out-live-demo-43ln)  
34. pnezis/tucan: An Elixir plotting library on top of VegaLite \- GitHub, accessed December 13, 2025, [https://github.com/pnezis/tucan](https://github.com/pnezis/tucan)  
35. Elixir and Rust is a good mix · The Phoenix Files \- Fly.io, accessed December 13, 2025, [https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/](https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/)  
36. Top Ten Reasons to Pair Phoenix with Rust for High-Performance ..., accessed December 13, 2025, [https://hexshift.medium.com/top-ten-reasons-to-pair-phoenix-with-rust-for-high-performance-elixir-applications-169a9a7a4486](https://hexshift.medium.com/top-ten-reasons-to-pair-phoenix-with-rust-for-high-performance-elixir-applications-169a9a7a4486)  
37. The difficulties deciding between Phoenix LiveView and traditional ..., accessed December 13, 2025, [https://devtalk.com/t/choosing-phoenix-liveview-the-difficulties-deciding-between-phoenix-liveview-and-traditional-frontend-frameworks/222945](https://devtalk.com/t/choosing-phoenix-liveview-the-difficulties-deciding-between-phoenix-liveview-and-traditional-frontend-frameworks/222945)  
38. Revolutionizing Data Visualization with Matplotex \- BigThinkCode, accessed December 13, 2025, [https://www.bigthinkcode.com/insights/data-visualization-with-matplotex](https://www.bigthinkcode.com/insights/data-visualization-with-matplotex)  
39. JavaScript interoperability — Phoenix LiveView v1.1.18 \- Hexdocs, accessed December 13, 2025, [https://hexdocs.pm/phoenix\_live\_view/js-interop.html](https://hexdocs.pm/phoenix_live_view/js-interop.html)  
40. Building High-Performance Real Time Dashboards with Phoenix ..., accessed December 13, 2025, [https://hexshift.medium.com/building-high-performance-real-time-dashboards-with-phoenix-liveview-and-rust-b6605124bef3](https://hexshift.medium.com/building-high-performance-real-time-dashboards-with-phoenix-liveview-and-rust-b6605124bef3)  
41. Customizing Phoenix LiveView's Diffing and Rendering for Ultra ..., accessed December 13, 2025, [https://dev.to/hexshift/customizing-phoenix-liveviews-diffing-and-rendering-for-ultra-high-performance-41db](https://dev.to/hexshift/customizing-phoenix-liveviews-diffing-and-rendering-for-ultra-high-performance-41db)  
42. How do I get better performance from LVGL for a plot app \- How-to, accessed December 13, 2025, [https://forum.lvgl.io/t/how-do-i-get-better-performance-from-lvgl-for-a-plot-app/4552](https://forum.lvgl.io/t/how-do-i-get-better-performance-from-lvgl-for-a-plot-app/4552)  
43. Top Ten Tips for Using Rust with Phoenix LiveView for High ..., accessed December 13, 2025, [https://dev.to/hexshift/top-ten-tips-for-using-rust-with-phoenix-liveview-for-high-performance-backends-48nb](https://dev.to/hexshift/top-ten-tips-for-using-rust-with-phoenix-liveview-for-high-performance-backends-48nb)  
44. plotters \- Rust, accessed December 13, 2025, [https://plotters-rs.github.io/rustdoc/plotters/](https://plotters-rs.github.io/rustdoc/plotters/)  
45. I Tried a Bunch of High-Performance JavaScript Charts. Here's What ..., accessed December 13, 2025, [https://www.ejschart.com/i-tried-a-bunch-of-high-performance-javascript-charts-heres-what-actually-felt-fast/](https://www.ejschart.com/i-tried-a-bunch-of-high-performance-javascript-charts-heres-what-actually-felt-fast/)  
46. My Thoughts on the uPlot Charting Library \- Casey Primozic, accessed December 13, 2025, [https://cprimozic.net/notes/posts/my-thoughts-on-the-uplot-charting-library/](https://cprimozic.net/notes/posts/my-thoughts-on-the-uplot-charting-library/)  
47. Best JavaScript Chart Libraries for Data Visualization \- DigitalOcean, accessed December 13, 2025, [https://www.digitalocean.com/community/tutorials/javascript-charts](https://www.digitalocean.com/community/tutorials/javascript-charts)  
48. Multi series sharing 1 x-axis with uPlot \#682 \- GitHub, accessed December 13, 2025, [https://github.com/leeoniya/uPlot/issues/682](https://github.com/leeoniya/uPlot/issues/682)  
49. When moving from JS to WASM is not worth it \- Zaplib post mortem, accessed December 13, 2025, [https://www.reddit.com/r/programming/comments/ufb1gh/when\_moving\_from\_js\_to\_wasm\_is\_not\_worth\_it/](https://www.reddit.com/r/programming/comments/ufb1gh/when_moving_from_js_to_wasm_is_not_worth_it/)  
50. Nx Tip of the Week \#3 \- Many Ways to Create Arrays\*, accessed December 13, 2025, [https://seanmoriarity.com/2021/03/04/nx-tip-of-the-week-3-many-ways-to-create-arrays/](https://seanmoriarity.com/2021/03/04/nx-tip-of-the-week-3-many-ways-to-create-arrays/)  
51. phoenix\_live\_view/guides/server/uploads.md at main \- GitHub, accessed December 13, 2025, [https://github.com/phoenixframework/phoenix\_live\_view/blob/master/guides/server/uploads.md](https://github.com/phoenixframework/phoenix_live_view/blob/master/guides/server/uploads.md)  
52. Represent vectors as binaries · Issue \#6 \- GitHub, accessed December 13, 2025, [https://github.com/pgvector/pgvector-elixir/issues/6](https://github.com/pgvector/pgvector-elixir/issues/6)  
53. Vix.Vips.Image — vix v0.35.0 \- Hexdocs, accessed December 13, 2025, [https://hexdocs.pm/vix/Vix.Vips.Image.html](https://hexdocs.pm/vix/Vix.Vips.Image.html)  
54. Piping binary data through liveView socket \- Elixir Forum, accessed December 13, 2025, [https://elixirforum.com/t/piping-binary-data-through-liveview-socket/39908](https://elixirforum.com/t/piping-binary-data-through-liveview-socket/39908)