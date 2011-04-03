module ActiveRecord
  
  # MONKEYPATCH This class is entirely new
  class ReferrableJoin

    attr_reader :association
    attr_accessor :relation
    
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
  
  module QueryMethods
    def build_joins(relation, joins)
      association_joins = []

      joins = @joins_values.map {|j| j.respond_to?(:strip) ? j.strip : j}.uniq

      joins.each do |join|
        # MONKEYPATCH Added ActiveRecord::ReferrableJoin to the array here.
        association_joins << join if [Hash, Array, Symbol, ActiveRecord::ReferrableJoin].include?(join.class) && !array_of_strings?(join)
      end

      stashed_association_joins = joins.grep(ActiveRecord::Associations::ClassMethods::JoinDependency::JoinAssociation)

      non_association_joins = (joins - association_joins - stashed_association_joins)
      custom_joins = custom_join_sql(*non_association_joins)

      join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(@klass, association_joins, custom_joins)

      join_dependency.graft(*stashed_association_joins)

      @implicit_readonly = true unless association_joins.empty? && stashed_association_joins.empty?

      to_join = []

      join_dependency.join_associations.each do |association|
        if (association_relation = association.relation).is_a?(Array)
          to_join << [association_relation.first, association.join_type, association.association_join.first]
          to_join << [association_relation.last, association.join_type, association.association_join.last]
        else 
          to_join << [association_relation, association.join_type, association.association_join]
        end
      end
      
      to_join.uniq.each do |left, join_type, right|
        relation = relation.join(left, join_type).on(*right)
      end

      relation.join(custom_joins)
    end
  end 
  
  
  module Associations
    module ClassMethods
      class JoinDependency
    
        def build(associations, parent = nil, join_type = Arel::InnerJoin)
          parent ||= @joins.last
          case associations
          # MONKEYPATCH Added ActiveRecord::ReferrableJoin here
          when Symbol, String, ActiveRecord::ReferrableJoin
            reflection = parent.reflections[associations.to_s.intern] or
              raise ConfigurationError, "Association named '#{ associations }' was not found; perhaps you misspelled it\?"
            unless join_association = find_join_association(reflection, parent)
              @reflections << reflection
              join_association = build_join_association(reflection, parent)
              # <MONKEYPATCH added this conditional
              if associations.kind_of?(ActiveRecord::ReferrableJoin)
                associations.mirror_relation(join_association.relation)
              end 
              # >MONKEYPATCH
              join_association.join_type = join_type
              @joins << join_association
              cache_joined_association(join_association)
            end
            join_association
          when Array
            associations.each do |association|
              build(association, parent, join_type)
            end
          when Hash
            associations.keys.sort{|a,b|a.to_s<=>b.to_s}.each do |name|
              join_association = build(name, parent, join_type)
              build(associations[name], join_association, join_type)
            end
          else
            raise ConfigurationError, associations.inspect
          end
        end
      end 
    end 
  end 
end 
