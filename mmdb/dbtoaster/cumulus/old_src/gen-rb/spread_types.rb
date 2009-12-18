#
# Autogenerated by Thrift
#
# DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
#


module PutFieldType
  VALUE = 1
  ENTRY = 2
  ENTRYVALUE = 3
  VALUE_MAP = {1 => "VALUE", 2 => "ENTRY", 3 => "ENTRYVALUE"}
  VALID_VALUES = Set.new([VALUE, ENTRY, ENTRYVALUE]).freeze
end

module AggregateType
  SUM = 1
  MAX = 2
  AVG = 3
  VALUE_MAP = {1 => "SUM", 2 => "MAX", 3 => "AVG"}
  VALID_VALUES = Set.new([SUM, MAX, AVG]).freeze
end

class NodeID
  include ::Thrift::Struct
  HOST = 1
  PORT = 2

  ::Thrift::Struct.field_accessor self, :host, :port
  FIELDS = {
    HOST => {:type => ::Thrift::Types::STRING, :name => 'host'},
    PORT => {:type => ::Thrift::Types::I32, :name => 'port'}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end

class MapEntry
  include ::Thrift::Struct
  SOURCE = 1
  KEY = 2

  ::Thrift::Struct.field_accessor self, :source, :key
  FIELDS = {
    SOURCE => {:type => ::Thrift::Types::I64, :name => 'source'},
    KEY => {:type => ::Thrift::Types::LIST, :name => 'key', :element => {:type => ::Thrift::Types::I64}}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end

class PutField
  include ::Thrift::Struct
  TYPE = 1
  NAME = 2
  VALUE = 3
  ENTRY = 4

  ::Thrift::Struct.field_accessor self, :type, :name, :value, :entry
  FIELDS = {
    TYPE => {:type => ::Thrift::Types::I32, :name => 'type', :enum_class => PutFieldType},
    NAME => {:type => ::Thrift::Types::STRING, :name => 'name'},
    VALUE => {:type => ::Thrift::Types::DOUBLE, :name => 'value', :optional => true},
    ENTRY => {:type => ::Thrift::Types::STRUCT, :name => 'entry', :class => MapEntry, :optional => true}
  }

  def struct_fields; FIELDS; end

  def validate
    unless @type.nil? || PutFieldType::VALID_VALUES.include?(@type)
      raise ::Thrift::ProtocolException.new(::Thrift::ProtocolException::UNKNOWN, 'Invalid value of field type!')
    end
  end

end

class SpreadException < ::Thrift::Exception
  include ::Thrift::Struct
  WHY = 1
  RETRY = 2

  ::Thrift::Struct.field_accessor self, :why, :retry
  FIELDS = {
    WHY => {:type => ::Thrift::Types::STRING, :name => 'why'},
    RETRY => {:type => ::Thrift::Types::BOOL, :name => 'retry', :optional => true}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end

class PutParams
  include ::Thrift::Struct
  PARAMS = 1

  ::Thrift::Struct.field_accessor self, :params
  FIELDS = {
    PARAMS => {:type => ::Thrift::Types::LIST, :name => 'params', :element => {:type => ::Thrift::Types::STRUCT, :class => PutField}}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end

class PutRequest
  include ::Thrift::Struct
  TEMPLATE = 1
  ID_OFFSET = 2
  NUM_GETS = 3

  ::Thrift::Struct.field_accessor self, :template, :id_offset, :num_gets
  FIELDS = {
    TEMPLATE => {:type => ::Thrift::Types::I64, :name => 'template'},
    ID_OFFSET => {:type => ::Thrift::Types::I64, :name => 'id_offset'},
    NUM_GETS => {:type => ::Thrift::Types::I64, :name => 'num_gets'}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end

class GetRequest
  include ::Thrift::Struct
  TARGET = 1
  ID_OFFSET = 2
  ENTRIES = 3

  ::Thrift::Struct.field_accessor self, :target, :id_offset, :entries
  FIELDS = {
    TARGET => {:type => ::Thrift::Types::STRUCT, :name => 'target', :class => NodeID},
    ID_OFFSET => {:type => ::Thrift::Types::I64, :name => 'id_offset'},
    ENTRIES => {:type => ::Thrift::Types::LIST, :name => 'entries', :element => {:type => ::Thrift::Types::STRUCT, :class => MapEntry}}
  }

  def struct_fields; FIELDS; end

  def validate
  end

end
