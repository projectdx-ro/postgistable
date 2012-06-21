module Rake
  class TableTask < Task
    #
    # convenience methods
    %w{point linestring polygon}.each do |type|
      module_eval <<-DEFINE
        def add_#{type}_column(o={}); o[:geom_type]='#{type.upcase}';add_spatial_column(o);end
        def add_multi#{type}_column(o={}); o[:geom_type]='MULTI#{type.upcase}';add_spatial_column(o);end
      DEFINE
    end

    def add_updated_at
      if @@db[table_name].columns!.include? :updated_at
        @@db.alter_table(table_name) do
          set_column_default :updated_at, :now.sql_function
        end
      else
        @@db.alter_table(table_name) do
          add_column :updated_at, DateTime, :default => :now.sql_function
        end
      end
      @@db.alter_table(table_name) do
        add_index :updated_at
      end
      add_updated_at_trigger
    end

    def add_updated_at_trigger
      run %Q/ CREATE OR REPLACE FUNCTION update_timestamp() RETURNS trigger AS $$
        BEGIN
          NEW.updated_at := now();
          RETURN NEW;
        END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER update_timestamp_trigger 
        BEFORE INSERT OR UPDATE ON  #{table_name_literal} 
        FOR EACH ROW EXECUTE PROCEDURE update_timestamp()
      /
    end

    # takes the same arguments as Sequel
     def add_spatial_index(*args)
       args.push :the_geom if args.empty?
       @@db.alter_table(table_name) do
         add_spatial_index(*args)
       end
     end
     
    def cleanup_geom_columns(options={})
      run %Q/SELECT Populate_Geometry_Columns('#{table_name}'::regclass)/
    end

    def add_spatial_column(options={})
      options[:column_name]||=:the_geom
      options[:geom_type]||='MULTIPOLYGON'
      options[:srid]||='4326'
      options[:dimensions]=2
      run %Q/SELECT AddGeometryColumn('#{table_name}',
                                           '#{options[:column_name]}',
                                           '#{options[:srid]}',
                                           '#{options[:geom_type]}',
                                           '#{options[:dimensions].to_s}')/
      add_spatial_index(options[:column_name].to_sym)
    end
    
    # add a column containing the centroid of the original geometry
    # options: 
    # :centroid_column (default 'the_geom_centroids)
    # :source_column (default 'the_geom')
    # :create_trigger (default true)
    # a spatial index is always created on the new column
    # 
    def add_centroids(options={})
      options[:centroid_column]||= :the_geom_centroids
      options[:source_column]||= :the_geom
      options[:create_trigger] ||= true

      add_point_column(:column_name => options[:centroid_column])
      run %Q/UPDATE #{table_name_literal} SET 
                   #{options[:centroid_column]}=ST_PointOnSurface(#{options[:source_column]})
                   WHERE #{options[:centroid_column]} IS NULL
                 /
      add_latlong_from_centroid_trigger(options)
    end

    def add_latlong_from_centroid_trigger(options={})
      centroid_column = options[:centroid_column]||=:the_geom_centroids
      source_column = options[:source_column]||=:the_geom
      @@db.alter_table(table_name) do
        add_column :latitude, Float
        add_column :longitude, Float
      end

    run %Q/
     CREATE OR REPLACE FUNCTION add_centroid_#{table_name}() returns trigger as $$
       DECLARE
         geom_type text;
       BEGIN
         geom_type := geometrytype(NEW.#{@@db.literal(source_column)});
         BEGIN
         -- we want to ignore rows that generate errors
         -- this is usually a bad geometry problem
           if geom_type = 'POINT' THEN
               NEW.latitude := st_y(NEW.#{@@db.literal(source_column)});
               NEW.longitude := st_x(NEW.#{@@db.literal(source_column)});
           elsif geom_type = 'MULTIPOLYGON' THEN
               NEW.the_geom_centroids := ST_PointOnSurface(NEW.#{@@db.literal(source_column)});
               NEW.latitude := st_y(NEW.#{@@db.literal(centroid_column)});
               NEW.longitude := st_x(NEW.#{@@db.literal(centroid_column)});
           end if;
         EXCEPTION
           WHEN internal_error THEN
           RETURN NULL;
         END;

         RETURN NEW;
       END;
     $$ language 'plpgsql';

     CREATE TRIGGER add_centroid
       BEFORE INSERT OR UPDATE ON #{table_name_literal}
       FOR EACH ROW EXECUTE PROCEDURE add_centroid_#{table_name}();
     /
    end
  end
end
    