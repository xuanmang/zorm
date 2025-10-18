//! 博客系统共享模型定义
//!
//! 定义了示例应用使用的所有数据模型：
//! - User: 用户模型
//! - Post: 文章模型
//! - Comment: 评论模型
//! - Tag: 标签模型
//! - PostTag: 文章-标签关联模型 (多对多)
//!
//! 每个模型都包含 `table_name` 常量，用于 ZORM 的表映射。

const std = @import("std");

/// 用户模型
pub const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "users";
};

/// 文章模型
pub const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    status: []const u8, // draft, published, archived
    published_at: ?i64,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "posts";
};

/// 评论模型
pub const Comment = struct {
    id: i64,
    post_id: i64,
    user_id: i64,
    content: []const u8,
    created_at: i64,

    pub const table_name = "comments";
};

/// 标签模型
pub const Tag = struct {
    id: i64,
    name: []const u8,

    pub const table_name = "tags";
};

/// 文章-标签关联模型 (多对多关系)
pub const PostTag = struct {
    post_id: i64,
    tag_id: i64,

    pub const table_name = "post_tags";
};
