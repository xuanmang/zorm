//! 共享数据模型定义
//!
//! 博客系统的核心数据结构

const std = @import("std");

/// 用户模型
pub const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    created_at: ?i64 = null, // Unix timestamp
    updated_at: ?i64 = null,

    pub const TableName = "users";

    /// 验证用户数据
    pub fn validate(self: User) !void {
        if (self.name.len == 0) return error.InvalidName;
        if (self.email.len == 0) return error.InvalidEmail;
        if (std.mem.indexOf(u8, self.email, "@") == null) {
            return error.InvalidEmailFormat;
        }
    }
};

/// 文章模型
pub const Post = struct {
    id: ?i64 = null,
    user_id: i64,
    title: []const u8,
    content: ?[]const u8 = null,
    status: Status = .draft,
    published_at: ?i64 = null,
    created_at: ?i64 = null,
    updated_at: ?i64 = null,

    pub const TableName = "posts";

    pub const Status = enum {
        draft,
        published,
        archived,

        pub fn toString(self: Status) []const u8 {
            return switch (self) {
                .draft => "draft",
                .published => "published",
                .archived => "archived",
            };
        }
    };

    pub fn validate(self: Post) !void {
        if (self.title.len == 0) return error.InvalidTitle;
        if (self.title.len > 255) return error.TitleTooLong;
    }
};

/// 评论模型
pub const Comment = struct {
    id: ?i64 = null,
    post_id: i64,
    user_id: i64,
    content: []const u8,
    created_at: ?i64 = null,

    pub const TableName = "comments";

    pub fn validate(self: Comment) !void {
        if (self.content.len == 0) return error.EmptyComment;
    }
};

/// 标签模型
pub const Tag = struct {
    id: ?i64 = null,
    name: []const u8,

    pub const TableName = "tags";

    pub fn validate(self: Tag) !void {
        if (self.name.len == 0) return error.EmptyTagName;
        if (self.name.len > 50) return error.TagNameTooLong;
    }
};

/// 文章标签关联表
pub const PostTag = struct {
    post_id: i64,
    tag_id: i64,

    pub const TableName = "post_tags";
};
