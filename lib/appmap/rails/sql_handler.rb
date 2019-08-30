require 'appmap/trace/tracer'

module AppMap
  module Rails
    class SQLHandler
      class SQLCall < AppMap::Trace::MethodEvent
        attr_accessor :payload

        def initialize(path, lineno, payload)
          super AppMap::Trace::MethodEvent.next_id, :call, SQLHandler, :call, path, lineno, false, Thread.current.object_id

          self.payload = payload
        end

        def to_h
          super.tap do |h|
            h[:sql_query] = {
              sql: payload[:sql],
              explain_sql: payload[:explain_sql],
              server_version: payload[:server_version],
              database_type: payload[:database_type],
              binds: (payload[:binds] || {}).keys.reduce({}) do |memo, key|
                memo.tap do |_|
                  memo[key] = self.class.display_string(payload[:binds][key])
                end
              end
            }
          end
        end
      end

      class SQLReturn < AppMap::Trace::MethodReturnIgnoreValue
        def initialize(path, lineno, parent_id, elapsed)
          super AppMap::Trace::MethodEvent.next_id, :return, SQLHandler, :call, path, lineno, false, Thread.current.object_id

          self.parent_id = parent_id
          self.elapsed = elapsed
        end
      end

      def call(_, started, finished, _, payload) # (name, started, finished, unique_id, payload)
        return if AppMap::Trace.tracers.empty?

        reentry_key = "#{self.class.name}#call"
        return if Thread.current[reentry_key] == true

        Thread.current[reentry_key] = true
        begin
          sql = payload[:sql].strip

          return unless WHITELIST.find { |keyword| sql.index(keyword) == 0 }

          # Detect whether a function call within a specified filename is present in the call stack.
          find_in_backtrace = lambda do |file_name, function_name|
            Thread.current.backtrace.find do |line|
              tokens = line.split(':')
              tokens.find { |t| t.rindex(file_name) == (t.length - file_name.length) } &&
                tokens.find { |t| t == "in `#{function_name}'" }
            end
          end

          # Ignore SQL calls which are made while establishing a new connection.
          # Example:
          # /path/to/ruby/2.6.0/gems/sequel-5.20.0/lib/sequel/connection_pool.rb:122:in `make_new'
          return if find_in_backtrace.call('lib/sequel/connection_pool.rb', 'make_new')

          # Ignore SQL calls which are made while inspecting the DB schema.
          # Example:
          # /path/to/ruby/2.6.0/gems/sequel-5.20.0/lib/sequel/model/base.rb:812:in `get_db_schema'
          return if find_in_backtrace.call('lib/sequel/model/base.rb', 'get_db_schema')

          require 'sequel'

          payload[:server_version] = Sequel::Model.db.server_version
          payload[:database_type] = Sequel::Model.db.database_type.to_s

          # Sequel::Postgres::Database (2.2ms)  EXPLAIN SELECT "id" FROM "scenarios" WHERE ("uuid" = 'd82ac3ef-dd71-4948-8ac1-5bce8bee1d0f') LIMIT 1
          # Limit  (cost=0.15..8.17 rows=1 width=4)
          #   ->  Index Scan using scenarios_uuid_key on scenarios  (cost=0.15..8.17 rows=1 width=4)
          #         Index Cond: (uuid = 'd82ac3ef-dd71-4948-8ac1-5bce8bee1d0f'::uuid)
          if Sequel::Model.db.database_type == :postgres
            begin
              payload[:explain_sql] = Sequel::Model.db[%(EXPLAIN #{sql})].all.map { |r| r.values[0] }.join("\n")
            rescue
              warn "Unable to explain query #{sql}: #{$!}"
            end
          end

          call = SQLCall.new(__FILE__, __LINE__, payload)
          AppMap::Trace.tracers.record_event(call)
          AppMap::Trace.tracers.record_event(SQLReturn.new(__FILE__, __LINE__, call.id, finished - started))
        ensure
          Thread.current[reentry_key] = nil
        end
      end

      WHITELIST = %w[SELECT INSERT UPDATE DELETE].freeze
    end
  end
end