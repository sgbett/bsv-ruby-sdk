# frozen_string_literal: true

module BSV
  module X402
    # Stores the set of protected route patterns and their per-route options.
    #
    # Routes are matched in registration order; the first matching pattern wins.
    # Patterns may be:
    #   - an exact string (e.g. +'/api/v1/resource'+)
    #   - a glob string containing +*+ (e.g. +'/api/v1/*'+)
    #   - a +Regexp+
    #
    # Glob wildcards match a single path segment (everything up to the next +/+
    # or the end of the string). Use a +Regexp+ for more complex matching.
    #
    # Per-route options override the global configuration:
    #   - +:amount_sats+  — payment amount for this route
    #   - +:bound_headers+ — header names to include in the request binding
    class RouteMap
      # Represents a single protected route entry.
      Route = Struct.new(:pattern, :options)

      def initialize
        @routes = []
      end

      # Registers a protected route pattern with optional overrides.
      #
      # @param pattern [String, Regexp] path pattern to protect
      # @param options [Hash] per-route overrides (+:amount_sats+, +:bound_headers+)
      def protect(pattern, options = {})
        @routes << Route.new(compile(pattern), options.freeze)
      end

      # Returns +true+ if any registered pattern matches +path+.
      #
      # @param path [String] the request path (e.g. +PATH_INFO+ from Rack env)
      # @return [Boolean]
      def protected?(path)
        !match(path).nil?
      end

      # Returns the first route whose pattern matches +path+, or +nil+.
      #
      # @param path [String]
      # @return [Route, nil]
      def match(path)
        @routes.find { |route| route.pattern.match?(path) }
      end

      # Returns +true+ if no routes have been registered.
      #
      # @return [Boolean]
      def empty?
        @routes.empty?
      end

      private

      # Compiles a string pattern or regexp into a +Regexp+.
      #
      # String patterns are treated as globs: +*+ matches any sequence of
      # non-slash characters. All other regex metacharacters are escaped.
      #
      # @param pattern [String, Regexp]
      # @return [Regexp]
      def compile(pattern)
        return pattern if pattern.is_a?(Regexp)

        # Escape everything, then substitute the glob wildcard back.
        escaped = Regexp.escape(pattern.to_s)
        # Replace the escaped asterisk with a non-slash wildcard.
        regex_src = escaped.gsub('\*', '[^/]*')
        Regexp.new("\\A#{regex_src}\\z")
      end
    end
  end
end
