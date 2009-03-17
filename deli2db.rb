#! /usr/bin/env ruby


## Time to beat, with rexml:
# % time ./deli2db.rb > /dev/null 
# ./deli2db.rb > /dev/null  3.72s user 0.18s system 99% cpu 3.909 total
# and we get:
# % time ./deli2db.rb  > /dev/null 
# ./deli2db.rb > /dev/null  0.54s user 0.08s system 99% cpu 0.626 total


require 'rubygems'
require 'hpricot'
require 'iconv'
conv = Iconv.new( "LATIN1", "UTF-8" )


Source_db = "/Users/seb/Library/Application Support/Delicious Library/Library Media Data.xml"

file = File.new( Source_db )
doc = Hpricot.XML( file )

uuids = doc.search("library/shelves/shelf[@name='to-be-read']/linkto").collect do |x|
  x.attributes["uuid"]
end

#puts uuids.inspect

doc.search("library/items/book") do |x|
  if not uuids.include? x.attributes["uuid"]
    next
  end
  title = conv.iconv( x.attributes["fullTitle"] )
  if x.attributes.has_key? "author" 
    author = conv.iconv( x.attributes["author"].sub("\n", ", ") )
    puts <<EOF
      <listitem>
	<para><citetitle>#{title}</citetitle>, #{author}</para>
      </listitem>
EOF
  else
    puts <<EOF
      <listitem>
        <para><citetitle>#{title}</citetitle></para>
      </listitem>
EOF
  end
end
