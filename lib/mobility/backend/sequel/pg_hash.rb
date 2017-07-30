module Mobility
  module Backend
=begin

Internal class used by Sequel backends backed by a Postgres data type (hstore,
jsonb).

=end
    class Sequel::PgHash
      include Sequel
      include HashValued
      include Stringify

      def translations
        model[attribute.to_sym]
      end

      setup do |attributes|
        method_overrides = Module.new do
          define_method :initialize_set do |values|
            attributes.each { |attribute| self[attribute.to_sym] = {} }
            super(values)
          end
          define_method :before_validation do
            attributes.each do |attribute|
              self[attribute.to_sym].delete_if { |_, v| v.blank? }
            end
            super()
          end
        end
        include method_overrides
        include Mobility::Sequel::ColumnChanges.new(attributes)
      end
    end
  end
end