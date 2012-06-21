$: << File.expand_path(File.dirname(__FILE__) + "/lib/")
$: << File.expand_path(File.dirname(__FILE__) + "/rake/")

require 'tabletask'
require 'shapefiletask'

file 'osm/seattle.osm.bz2' do |t|
  sh %Q{cd osm && wget --timestamping http://osm-metro-extracts.s3.amazonaws.com/seattle.osm.bz2}
end

file 'osm/seattle.osm' => 'osm/seattle.osm.bz2' do |t|
  sh %Q{bzip2 -f -k -d osm/seattle.osm.bz2}
end

file 'osm/default.style'

table :seattle_osm_line => ['osm/default.style','osm/seattle.osm'] do |t|
  t.load_osmfile('osm/seattle.osm', :style => 'osm/default.style')
  t.add_updated_at
end
table :seattle_osm_point => :seattle_osm_line do |t|
  t.add_updated_at
end
table :seattle_osm_polygon => :seattle_osm_line do |t|
  t.add_updated_at
end
table :seattle_osm_roads  => :seattle_osm_line do |t|
  t.add_updated_at
end

task :seattle_osm => [:seattle_osm_roads, :seattle_osm_polygon, :seattle_osm_point, :seattle_osm_line ]

table :seattle_rails => [:seattle_osm] do |t|
  t.drop_table
  t.run %Q/
    SELECT osm_id as gid,railway,name,route_name,updated_at, way as the_geom 
      INTO #{t.table_name_literal} 
      FROM "seattle_osm_line" 
      WHERE railway IS NOT NULL/
  t.add_spatial_index
  t.add_updated_at
  t.cleanup_geom_columns
end

shps=Dir['shps/rlis/**/*.[Ss][Hh][Pp]']

tables=[]
shps.each do |shp|
  # shapefile shp
  shapefile shp
  table_name=File.basename(shp, '.shp')
  tables.push(table_name)
  desc "load #{shp} into postgis table #{table_name}"
  table table_name => shp do |t|
    puts "loading #{table_name}"
    t.load_shapefile(shp) || t.drop_table
  end
end

shapefile 'shps/world.shp'
shapefile 'shps/world_lrg.shp'

table :world_simple => 'shps/world.shp' do |t|
  t.load_shapefile('shps/world.shp')
end
table :world_detail => 'shps/world_lrg.shp' do |t|
  t.load_shapefile('shps/world_lrg.shp')
end

table :world => [:world_simple, :world_detail] do |t|
  t.drop_table
  t.run %Q/
    SELECT s.*,d.continent INTO #{t.name} 
      FROM world_simple as s
      JOIN (SELECT distinct iso_cc,continent FROM world_detail) d ON s.iso_2digit=d.iso_cc
      / 
  t.add_spatial_index
  t.add_updated_at
  t.cleanup_geom_columns
end

task :default => tables

# table :something => [:park_dst, :nbo_hood] do|t|
#   run %Q/ select * from park_dst,nbo_hood
#       /
# end
    