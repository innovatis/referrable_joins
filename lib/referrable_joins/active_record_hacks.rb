module ActiveRecord
  
  module SpawnMethods
    def merge(r)
      merged_relation = clone
      return merged_relation unless r
      return to_a & r if r.is_a?(Array)

      Relation::ASSOCIATION_METHODS.each do |method|
        value = r.send(:"#{method}_values")

        unless value.empty?
          if method == :includes
            merged_relation = merged_relation.includes(value)
          else
            merged_relation.send(:"#{method}_values=", value)
          end
        end
      end

      (Relation::MULTI_VALUE_METHODS - [:joins, :where, :order]).each do |method|
        value = r.send(:"#{method}_values")
        merged_relation.send(:"#{method}_values=", merged_relation.send(:"#{method}_values") + value) if value.present?
      end

      order_value = r.order_values
      if order_value.present?
        if r.reorder_flag
          merged_relation.order_values = order_value
        else
          merged_relation.order_values = merged_relation.order_values + order_value
        end
      end
      
      # MONKEYPATCH Only change, right here.
      merged_relation = merged_relation.outer_joins(r.outer_joins_values).inner_joins(r.inner_joins_values)

      merged_wheres = @where_values + r.where_values

      unless @where_values.empty?
        # Remove duplicates, last one wins.
        seen = Hash.new { |h,table| h[table] = {} }
        merged_wheres = merged_wheres.reverse.reject { |w|
          nuke = false
          if w.respond_to?(:operator) && w.operator == :==
            name              = w.left.name
            table             = w.left.relation.name
            nuke              = seen[table][name]
            seen[table][name] = true
          end
          nuke
        }.reverse
      end

      merged_relation.where_values = merged_wheres

      Relation::SINGLE_VALUE_METHODS.reject {|m| m == :lock}.each do |method|
        value = r.send(:"#{method}_value")
        merged_relation.send(:"#{method}_value=", value) unless value.nil?
      end

      merged_relation.lock_value = r.lock_value unless merged_relation.lock_value

      # Apply scope extension modules
      merged_relation.send :apply_modules, r.extensions

      merged_relation
    end
  end 

  class ReflectionTable
   
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
   
  class Base
    class << self
      delegate :outer_joins, :inner_joins, :to => :scoped
      
      def reflection_table(reflection)
        ActiveRecord::ReflectionTable.new(self.reflections[reflection].table_name.to_sym, reflection)
      end 
      
    end 
  end 

  module QueryMethods
    
    attr_accessor :outer_joins_values, :inner_joins_values

    def joins(*args)
      relation = clone

      args.flatten!
      relation.inner_joins_values ||= []
      relation.inner_joins_values += args unless args.blank?

      relation
    end
    alias_method :inner_joins, :joins
    
    def outer_joins(*args)
      relation = clone

      args.flatten!
      relation.outer_joins_values ||= []
      relation.outer_joins_values += args unless args.blank?

      relation
    end

    def build_arel
      arel = table
      
      @inner_joins_values||=[]
      @outer_joins_values||=[]
      
      arel = build_joins(arel, @inner_joins_values, @outer_joins_values) unless @outer_joins_values.blank? && @inner_joins_values.blank?

      (@where_values - ['']).uniq.each do |where|
        where = Arel.sql(where) if String === where
        arel = arel.where(Arel::Nodes::Grouping.new(where))
      end

      arel = arel.having(*@having_values.uniq.reject{|h| h.blank?}) unless @having_values.empty?

      arel = arel.take(@limit_value) if @limit_value
      arel = arel.skip(@offset_value) if @offset_value

      arel = arel.group(*@group_values.uniq.reject{|g| g.blank?}) unless @group_values.empty?

      arel = arel.order(*@order_values.uniq.reject{|o| o.blank?}) unless @order_values.empty?

      arel = build_select(arel, @select_values.uniq)

      arel = arel.from(@from_value) if @from_value
      arel = arel.lock(@lock_value) if @lock_value

      arel
    end

    
    def build_joins(relation, inner_joins, outer_joins)
      inner_association_joins = []
      outer_association_joins = []

      inner_joins = @inner_joins_values.map {|j| j.respond_to?(:strip) ? j.strip : j}.uniq
      outer_joins = @outer_joins_values.map {|j| j.respond_to?(:strip) ? j.strip : j}.uniq

      inner_joins.each do |join|
        inner_association_joins << join if [Hash, Array, Symbol, ActiveRecord::ReflectionTable].include?(join.class) && !array_of_strings?(join)
      end

      outer_joins.each do |join|
        outer_association_joins << join if [Hash, Array, Symbol, ActiveRecord::ReflectionTable].include?(join.class) && !array_of_strings?(join)
      end

      stashed_association_joins = (inner_joins + outer_joins).grep(ActiveRecord::Associations::ClassMethods::JoinDependency::JoinAssociation)

      non_association_joins = (outer_joins + inner_joins - outer_association_joins - inner_association_joins - stashed_association_joins)
      custom_joins = custom_join_sql(*non_association_joins)

      join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(@klass, inner_association_joins, outer_association_joins, custom_joins)

      join_dependency.graft(*stashed_association_joins)

      @implicit_readonly = true unless inner_association_joins.empty? && outer_association_joins.empty? && stashed_association_joins.empty?

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

        def initialize(base, inner_associations, outer_associations, joins)
          @joins                 = [JoinBase.new(base, joins)]
          @associations          = {}
          @reflections           = []
          @base_records_hash     = {}
          @base_records_in_order = []
          @table_aliases         = Hash.new { |aliases, table| aliases[table] = 0 }
          @table_aliases[base.table_name] = 1
          build(outer_associations, @joins.first, Arel::OuterJoin)
          build(inner_associations, @joins.first, Arel::InnerJoin)
        end
    
        def build(associations, parent = nil, join_type = Arel::InnerJoin)
          parent ||= @joins.last
          case associations
          # MONKEYPATCH Added ActiveRecord::ReflectionTable here
          when Symbol, String, ActiveRecord::ReflectionTable
            reflection = parent.reflections[associations.to_s.intern] or
              raise ConfigurationError, "Association named '#{ associations }' was not found; perhaps you misspelled it\?"
            unless join_association = find_join_association(reflection, parent)
              @reflections << reflection
              join_association = build_join_association(reflection, parent)
              # <MONKEYPATCH added this conditional
              if associations.kind_of?(ActiveRecord::ReflectionTable)
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
