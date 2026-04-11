# frozen_string_literal: true

require 'mcp'

module BSV
  module MCP
    # Builds and returns an MCP::Server instance configured for the BSV SDK.
    #
    # Tools are registered here as the feature set grows. Currently returns an
    # empty tool list — Tasks 2 and 3 will add concrete tools.
    #
    # Logging goes to $stderr only; $stdout is the MCP protocol channel.
    module Server
      # Builds the MCP::Server instance with the given config.
      #
      # @param config [BSV::MCP::Config] network and ARC configuration
      # @return [::MCP::Server]
      def self.build(config = nil)
        config ||= Config.new

        ::MCP::Server.new(
          name: 'bsv-sdk',
          version: BSV::VERSION,
          instructions: server_instructions(config),
          tools: registered_tools
        )
      end

      # Returns the list of tool classes registered with this server.
      #
      # @return [Array<Class>] tool classes inheriting from MCP::Tool
      def self.registered_tools
        [
          Tools::GenerateKey,
          Tools::DecodeTx,
          Tools::FetchUtxos,
          Tools::FetchTx,
          Tools::CheckBalance,
          Tools::BroadcastP2pkh
        ]
      end

      # Starts the MCP server over stdio using the standard StdioTransport.
      # Blocks until the client disconnects or the process is interrupted.
      #
      # @param config [BSV::MCP::Config] network and ARC configuration
      def self.start(config = nil)
        config ||= Config.new

        warn "BSV MCP server starting (network: #{config.network}, version: #{BSV::VERSION})"

        server = build(config)
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        transport.open
      end

      # @api private
      def self.server_instructions(config)
        <<~INSTRUCTIONS.strip
          BSV blockchain SDK tools. Network: #{config.network}.
          All operations target the #{config.network} network unless otherwise noted.
          Keys are passed as WIF strings and are never persisted by the server.
        INSTRUCTIONS
      end
      private_class_method :server_instructions
    end
  end
end
