import JavaScriptCore

public struct SVGOptimiserError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// svgo in its own JavaScriptCore context. Callable from any thread, one optimise at a time: a large SVG takes long
/// enough to stall the main thread, so the iOS tool runs it in the background.
public final class SVGOptimiserEngine: @unchecked Sendable {

    private let context: JSContext
    private let lock = NSLock()

    public init?() {
        guard let ctx = JSContext(),
              let url = Bundle.module.url(forResource: "svgo.browser", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var loadFailed = false
        ctx.exceptionHandler = { _, _ in loadFailed = true }
        ctx.evaluateScript(js)
        guard !loadFailed else { return nil }
        ctx.exceptionHandler = { _, _ in }
        self.context = ctx
    }

    public func optimise(_ svg: String) -> Result<String, SVGOptimiserError> {
        lock.withLock { run(svg) }
    }

    private func run(_ svg: String) -> Result<String, SVGOptimiserError> {
        context.setObject(svg, forKeyedSubscript: "svgInput" as NSString)

        let script = """
        (function() {
            try {
                var result = optimize(svgInput, {
                    multipass: true,
                    plugins: [
                        "preset-default",
                        "removeDimensions",
                        { name: "removeAttrs", params: { attrs: "(data-.*)" } }
                    ]
                });
                return JSON.stringify({ data: result.data });
            } catch(e) {
                return JSON.stringify({ error: e.message || String(e) });
            }
        })()
        """

        guard let jsResult = context.evaluateScript(script),
              let jsonString = jsResult.toString(),
              jsonString != "undefined",
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(SVGOptimiserError(message: "Failed to optimise SVG"))
        }

        if let error = json["error"] as? String {
            return .failure(SVGOptimiserError(message: error))
        }

        guard let optimised = json["data"] as? String else {
            return .failure(SVGOptimiserError(message: "No output from optimiser"))
        }

        return .success(optimised)
    }
}
