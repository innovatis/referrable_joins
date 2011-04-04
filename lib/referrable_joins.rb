class ReferrableJoin

  attr_reader :association
  attr_accessor :relation

  def [](name)
    relation.columns.find { |col| col.name == name }
  end 
  
  def initialize(table, association)
    @association = association
    @relation = Arel::Table.new(table, ActiveRecord::Base)
  end 
  
  def mirror_relation(other)
    ["engine", "columns", "table_alias"].each do |ivar|
      @relation.instance_variable_set("@#{ivar}", other.instance_variable_get("@#{ivar}"))
    end 
  end 
  
  def to_s
    @association.to_s
  end 
  
end 

path = File.join(File.dirname(__FILE__), 'referrable_joins')
$:.unshift(path) unless $:.include?(path)

require 'referrable_joins/active_record_hacks'

