const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const Channel = struct { name: []const u8, group: []const u8, logo: []const u8, m3u: []const u8 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator();

    var channels_map = std.StringHashMap(ArrayList(Channel)).init(allocator.*);
    defer channels_map.deinit();

    const playlist_content = try readInputFile(allocator.*, "playlist.m3u8");
    var channel_lines = try filter_playlist_contents(allocator.*, playlist_content, "\n");
    try get_channels_from_playlist(allocator.*, channel_lines, &channels_map);

    print_channels(&channels_map);
}

fn print_channels(channel_list: *std.StringHashMap(ArrayList(Channel))) void {
    var iterator = channel_list.iterator();
    while (iterator.next()) |channel_group| {
        print("{s}\n", .{channel_group.key_ptr.*});
        for (channel_group.value_ptr.*.items) |channel| {
            print("    - {s}\n", .{channel.name});
            print("    - {s}\n\n", .{channel.m3u});
        }
    }
}

fn parse_channel_info(channel_info: []const u8) Channel {
    var split_iterator = std.mem.split(u8, channel_info, "tvg-name=");
    _ = split_iterator.next();
    split_iterator = std.mem.split(u8, split_iterator.next().?, "tvg-logo=");
    var channel_name = split_iterator.next().?;
    split_iterator = std.mem.split(u8, split_iterator.next().?, "group-title=");
    var logo_url = split_iterator.next().?;
    split_iterator = std.mem.split(u8, split_iterator.next().?, ",");
    var channel_group = split_iterator.next().?;
    return Channel{ .name = channel_name, .group = channel_group, .logo = logo_url, .m3u = "" };
}

fn get_channels_from_playlist(allocator: std.mem.Allocator, channels: [][]const u8, channels_hashmap: *std.StringHashMap(ArrayList(Channel))) !void {
    var index: usize = 0;
    while (index < channels.len - 1) {
        var channel_info = channels[index];
        var channel = parse_channel_info(channel_info);
        channel.m3u = channels[index + 1];

        var group_channels = try channels_hashmap.*.getOrPut(channel.group);
        if (!group_channels.found_existing) {
            var group_channel_list = ArrayList(Channel).init(allocator);
            defer group_channel_list.deinit();
            group_channels.value_ptr.* = group_channel_list;
        }

        try group_channels.value_ptr.*.append(channel);

        index = index + 2;
    }
}

fn filter_playlist_contents(allocator: std.mem.Allocator, content: []const u8, separator: []const u8) ![][]const u8 {
    var lines = ArrayList([]const u8).init(allocator);
    defer lines.deinit();
    var readIter = std.mem.split(u8, content, separator);
    while (readIter.next()) |line| {
        var header = std.mem.indexOf(u8, line, "#EXTM3U");
        var session = std.mem.indexOf(u8, line, "#EXT-X-SESSION-DATA");
        // I just want the channel line and the url.
        if (header != null or session != null) {
            continue;
        }
        try lines.append(line);
    }

    return try lines.toOwnedSlice();
}

fn readInputFile(allocator: std.mem.Allocator, file_name: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();
    const stat = try file.stat();
    const fileSize = stat.size;
    return try file.reader().readAllAlloc(allocator, fileSize);
}
