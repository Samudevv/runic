/*
This file has been copied from https://github.com/SabeDoesThings/odin-tiled.
It has been slightly modified to allow bindings to C.
Here is the license of said project:

MIT License

Copyright (c) 2024 SabeDoesThings

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
package tiled

import runtime "base:runtime"
import json "core:encoding/json"
import fmt "core:fmt"
import os "core:os"

/*
	Based on the JSON Map Format for Tiled 1.2.
	https://doc.mapeditor.org/en/stable/reference/json-map-format/

	TODO:
		- This needs to be extensively tested. You can help by e.g.
		  sending me your Tiled files (as JSON) in order to give me
		  testing material.
		- Comment all fields with the description in the link above.
		  Textually separate optional fields and describe them as such.
		- Add the omitempty tag where appropriate.
*/

// parse_tilemap takes a Tiled tilemap JSON file
// and converts it into an Odin data structure.
@(export)
parse_tilemap :: proc "c" (path: string) -> Map {
    context = runtime.default_context()

    m: Map
    jdata, ok := os.read_entire_file(path)
    if !ok {
        fmt.print("Failed to read file: ", path, "\n")
        return m
    }

    err := json.unmarshal(jdata, &m)
    if err != nil {
        fmt.print("Failed to unmarshal JSON: ", err, "\n")
        return m
    }
    return m
}

// parse_tileset takes a Tiled tileset JSON file
// and converts it into an Odin data structure.
@(export)
parse_tileset :: proc "c" (path: string) -> Tileset {
    context = runtime.default_context()

    ts: Tileset
    jdata, ok := os.read_entire_file(path)
    if !ok {
        fmt.print("Failed to read file: ", path, "\n")
        return ts
    }

    err := json.unmarshal(jdata, &ts)
    if err != nil {
        fmt.print("Failed to unmarshal JSON: ", err, "\n")
        return ts
    }
    return ts
}

// Map describes a Tiled map.
Map :: struct {
    background_color: string `json:"backgroundcolor"`, // Hex-formatted color (#RRGGBB or #AARRGGBB) (optional).
    height:           i32 `json:"height"`, // Number of tile rows.
    hex_side_length:  i32 `json:"hexsidelength"`, // Length of the side of a hex tile in pixels.
    infinite:         bool `json:"infinite"`, // Whether the map has infinite dimensions.
    layers:           []Layer `json: "layers"`, // Array of Layers.
    next_layer_id:    i32 `json: "nextlayerid"`, // Auto-increments for each layer.
    next_object_id:   i32 `json: "nextobjectid"`, // Auto-increments for each placed object.
    orientation:      string `json: "orientation"`, // "orthogonal", "isometric", "staggered" or "hexagonal".
    properties:       []Property `json: "properties"`, // A list of properties (name, value, type).
    render_order:     string `json: "renderorder"`, // Rendering direction (orthogonal maps only).
    stagger_axis:     string `json: "staggeraxis"`, // "x" or "y" (staggered / hexagonal maps only).
    stagger_index:    string `json: "staggerindex"`, // "odd" or "even" (staggered / hexagonal maps only).
    tiled_version:    string `json: "tiledversion"`, // The Tiled version used to save the file.
    tileheight:       i32 `json: "tileheight"`, // Map grid height.
    tilesets:         []Tileset `json: "tilesets"`, // Array of Tilesets.
    tilewidth:        i32 `json: "tilewidth"`, // Map grid width.
    type:             string `json: "type"`, // "map" (since 1.0).
    version:          f32 `json: "version"`, // The JSON format version.
    width:            i32 `json: "width"`, // Number of tile columns.
}

Property :: struct {
    name:  string `json: "name"`, // Name of property
    type:  string `json: "type"`, // Type of property value
    value: any `json: "value"`, // Value of property
}

Layer :: struct {
    // Common
    id:                i32 `json: "id"`, // Incremental id - unique across all layers
    name:              string `json: "name"`, // Name assigned to this layer
    type:              string `json: "type"`, // "tilelayer, "objectgroup, "imagelayer or "group"
    visible:           bool `json: "visible"`, // Whether layer is shown or hidden in editor
    width:             i32 `json: "width"`, // Column count. Same as map width for fixed-size maps
    height:            i32 `json: "height"`, // Row count. Same as map height for fixed-size maps
    x:                 i32 `json: "x"`, // Horizontal layer offset in tiles. Always 0
    y:                 i32 `json: "y"`, // Vertical layer offset in tiles. Always 0
    offsetx:           f32 `json: "offsetx"`, // Horizontal layer offset in pixels (default: 0)
    offsety:           f32 `json: "offsety"`, // Vertical layer offset in pixels (default: 0)
    opacity:           f32 `json: "opacity"`, // Value between 0 and 1
    properties:        []Property `json: "properties"`, // A list of properties (name, value, type)

    // TileLayer only
    chunks:            []Chunk `json: "chunks"`, // Array of chunks (optional, for ininite maps)
    compression:       string `json: "compression"`, // "zlib", "gzip" or empty (default)
    data:              []i32 `json: "data"`, // Array or string. Array of unsigned int (GIDs) or base64-encoded data
    encoding:          string `json: "encoding"`, // "csv" (default) or "base64"

    // ObjectGroup only
    objects:           []Object `json: "objects"`, // Array of objects
    drawOrder:         string `json: "drawOrder"`, // "topdown" (default) or "index"

    // Group only
    layers:            []Layer `json: "layers"`, // Array of layers

    // ImageLayer only
    image:             string `json: "image"`, // Image used by this layer
    transparent_color: string `json: "transparentcolor"`, // Hex-formatted color (#RRGGBB) (optional)
}

// Chunk is used to store the tile layer data for infinite maps.
Chunk :: struct {
    data:   any `json: "data"`, // Array of unsigned int (GIDs) or base64-encoded data
    height: i32 `json: "height"`, // Height in tiles
    width:  i32 `json: "width"`, // Width in tiles
    x:      i32 `json: "x"`, // X coordinate in tiles
    y:      i32 `json: "y"`, // Y coordinate in tiles
}

Object :: struct {
    id:         i32 `json: "id"`, // Incremental id - unique across all objects
    gid:        i32 `json: "gid"`, // GID, only if object comes from a Tilemap
    name:       string `json: "name"`, // String assigned to name field in editor
    type:       string `json: "type"`, // String assigned to type field in editor
    x:          f64 `json: "x"`, // X coordinate in pixels
    y:          f64 `json: "y"`, // Y coordinate in pixels
    width:      f64 `json: "width"`, // Width in pixels, ignored if using a gid
    height:     f64 `json: "height"`, // Height in pixels, ignored if using a gid
    visible:    bool `json: "visible"`, // Whether object is shown in editor
    ellipse:    bool `json: "ellipse"`, // Used to mark an object as an ellipse
    point:      bool `json: "point"`, // Used to mark an object as a point
    polygon:    []Coordinate `json: "polygon"`, // A list of x,y coordinates in pixels
    polyline:   []Coordinate `json: "polyline"`, // A list of x,y coordinates in pixels
    properties: []Property `json: "properties"`, // A list of properties (name, value, type)
    rotation:   f64 `json: "rotation"`, // Angle in degrees clockwise
    template:   string `json: "template"`, // Reference to a template file, in case object is a template instance
    text:       map[string]i32 `json: "text"`, // String key-value pairs
}

Coordinate :: struct {
    x: f32 `json: "x"`,
    y: f32 `json: "y"`,
}

Offset :: struct {
    x: f32 `json: "x"`,
    y: f32 `json: "y"`,
}

// A Tileset that associates information with each tile, like its image
// path or terrain type, may include a Tiles array property. Each tile
// has an ID property, which specifies the local ID within the tileset.
//
// For the terrain information, each value is a length-4 array where
// each element is the index of a terrain on one corner of the tile.
// The order of indices is: top-left, top-right, bottom-left, bottom-right.
Tileset :: struct {
    firstgid:          i32 `json: "firstgid"`, // GID corresponding to the first tile in the set
    source:            string `json: "source"`, // Only used if an external tileset is referred to
    name:              string `json: "name"`, // Name given to this tileset
    type:              string `json: "type"`, // "tileset" (for tileset files, since 1.0)
    columns:           i32 `json: "columns"`, // The number of tile columns in the tileset
    image:             string `json: "image"`, // Image used for tiles in this set
    image_width:       i32 `json: "imagewidth"`, // Width of source image in pixels
    image_height:      i32 `json: "imageheight"`, // Height of source image in pixels
    margin:            i32 `json: "margin"`, // Buffer between image edge and first tile (pixels)
    spacing:           i32 `json: "spacing"`, // Spacing between adjacent tiles in image (pixels)
    tile_count:        i32 `json: "tilecount"`, // The number of tiles in this tileset
    tilewidth:         i32 `json: "tilewidth"`, // Maximum width of tiles in this set
    tileheight:        i32 `json: "tileheight"`, // Maximum height of tiles in this set
    transparent_color: string `json: "transparentcolor"`, // Hex-formatted color (#RRGGBB) (optional)
    tile_offset:       Offset `json: "tileoffset"`, // https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#tmx-tileoffset
    grid:              Grid `json: "grid"`, // (Optional) https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#tmx-grid
    properties:        []Property `json: "properties"`, // A list of properties (name, value, type)
    terrains:          []Terrain `json: "terrains"`, // Array of Terrains (optional)
    tiles:             []Tile `json: "tiles"`, // Array of Tiles (optional)
    wang_sets:         []WangSet `json: "wangsets"`, // Array of Wang sets (since 1.1.5)
}

// The Grid element is only used in case of isometric orientation,
// and determines how tile overlays for terrain and collision information are rendered.
Grid :: struct {
    orientation: string `json: "orientation"`, // "orthogonal" or "isometric"
    width:       i32 `json: "width"`, // Width of a grid cell
    height:      i32 `json: "height"`, // Height of a grid cell
}

Tile :: struct {
    id:           i32 `json: "id"`, // Local ID of the tile
    type:         string `json: "type"`, // The type of the tile (optional)
    properties:   []Property `json: "properties"`, // A list of properties (name, value, type)
    animation:    []Frame `json: "animation"`, // Array of Frames
    terrain:      []i32 `json: "terrain"`, // Index of terrain for each corner of tile
    image:        string `json: "image"`, // Image representing this tile (optional)
    image_height: i32 `json: "imageheight"`, // Height of the tile image in pixels
    image_width:  i32 `json: "imagewidth"`, // Width of the tile image in pixels
    object_group: Layer `json: "objectgroup"`, // Layer with type "objectgroup" (optional)
}

Frame :: struct {
    furation: i32 `json: "furation"`, // Frame duration in milliseconds
    tile_id:  i32 `json: "tileid"`, // Local tile ID representing this frame
}

Terrain :: struct {
    name: string `json: "name"`, // Name of terrain
    tile: i32 `json: "tile"`, // Local ID of tile representing terrain
}

WangSet :: struct {
    corner_colors: []WangColor `json: "cornercolors"`, // Array of Wang colors
    edge_colors:   []WangColor `json: "edgecolors"`, // Array of Wang colors
    name:          string `json: "name"`, // Name of the Wang set
    tile:          i32 `json: "tile"`, // Local ID of tile representing the Wang set
    wang_tiles:    []WangTile `json: "wangtiles"`, // Array of Wang tiles
}

WangColor :: struct {
    color:       string `json: "color"`, // Hex-formatted color (#RRGGBB or #AARRGGBB)
    name:        string `json: "name"`, // Name of the Wang color
    probability: f32 `json: "probability"`, // Probability used when randomizing
    tile:        i32 `json: "tile"`, // Local ID of tile representing the Wang color
}

WangTile :: struct {
    tile_id: i32 `json: "tileid"`, // Local ID of tile
    wang_id: [8]byte `json: "wangid"`, // Array of Wang color indexes (uchar[8])
    d_flip:  bool `json: "dflip"`, // Tile is flipped diagonally
    h_flip:  bool `json: "hflip"`, // Tile is flipped horizontally
    v_flip:  bool `json: "vflip"`, // Tile is flipped vertically
}

// An ObjectTemplate is written to its own file
// and referenced by any instances of that template.
ObjectTemplate :: struct {
    type:    string `json: "type"`, // "template"
    tileset: Tileset `json: "tileset"`, // External tileset used by the template (optional)
    object:  Object `json: "object"`, // The object instantiated by this template
}
