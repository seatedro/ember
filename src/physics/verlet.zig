const std = @import("std");
const core = @import("../core/types.zig");

const Vec2 = core.Vec2;

/// A tiny 2-D physics module providing Verlet integration.
pub const Particle = struct {
    pub const Self = @This();

    position: Vec2,
    radius: f32,
    color: @Vector(4, f32),

    /// Position in the previous simulation step.
    prev_position: Vec2,

    /// Accumulated acceleration for the current step (m/s^2 in world units).
    /// Reset to zero at the end of each step.
    acceleration: Vec2 = Vec2{ 0.0, 0.0 },

    pub fn init(pos: Vec2, radius: f32, color: @Vector(4, f32)) Self {
        return .{ .position = pos, .prev_position = pos, .radius = radius, .color = color };
    }

    pub fn accelerate(self: *Self, acceleration: Vec2) void {
        self.acceleration += acceleration;
    }

    /// Integrate the particle forward by `dt` seconds using Verlet integration.
    pub fn integrate(self: *Self, dt: f32) void {
        // u_t = x_t - x_{t-1} : u_t is previous velocity
        const ut = self.position - self.prev_position;
        // x_{n+1} = 2x_n - x_{n-1} + a * dt^2
        self.prev_position = self.position;
        self.position += ut + self.acceleration * @as(Vec2, @splat(dt * dt));
        // Clear the acceleration for the next frame.
        self.acceleration = Vec2{ 0.0, 0.0 };
    }
};

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    particles: std.ArrayList(Particle),
    gravity: Vec2,

    has_boundary: bool = false,
    boundary_center: Vec2 = Vec2{ 0.0, 0.0 },
    boundary_radius: f32 = 0.0,

    solver_iterations: usize = 1,

    pub fn init(a: std.mem.Allocator, gravity: Vec2) !Self {
        return .{
            .allocator = a,
            .particles = std.ArrayList(Particle).init(a),
            .gravity = gravity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.particles.deinit();
    }

    pub fn setBoundaryCircle(self: *Self, center: Vec2, radius: f32, iterations: usize) void {
        self.boundary_center = center;
        self.boundary_radius = radius;
        self.solver_iterations = if (iterations == 0) 1 else iterations;
        self.has_boundary = true;
    }

    pub fn addParticle(self: *Self, pos: Vec2, radius: f32, color: @Vector(4, f32)) !void {
        try self.particles.append(Particle.init(pos, radius, color));
    }

    pub fn addParticles(self: *Self, positions: []const Vec2) !void {
        try self.particles.ensureCapacity(self.particles.items.len + positions.len);
        for (positions) |p| {
            // Default to white color for this function - could be updated later if needed
            self.particles.appendAssumeCapacity(Particle.init(p, 20.0, @Vector(4, f32){ 1.0, 1.0, 1.0, 1.0 }));
        }
    }

    /// Step the whole world forward by `dt` seconds.
    /// A single global gravity is applied as an acceleration to all particles.
    pub fn step(self: *Self, dt: f32) void {
        self.applyGravity();
        for (self.particles.items) |*p| {
            p.integrate(dt);
        }

        self.checkCollisions();

        if (self.has_boundary) {
            for (0..self.solver_iterations) |_| {
                for (self.particles.items) |*p| {
                    enforceCircleBound(self, p);
                }
            }
        }
    }

    /// Apply a force/acceleration to the particle (will be accumulated until the next step).
    pub fn applyGravity(self: *Self) void {
        for (self.particles.items) |*p| {
            p.accelerate(self.gravity);
        }
    }

    pub inline fn len(self: *const Self) usize {
        return self.particles.items.len;
    }

    fn enforceCircleBound(self: *Self, p: *Particle) void {
        const to = self.boundary_center - p.position;
        const dist_sq = to[0] * to[0] + to[1] * to[1];
        const dist = @sqrt(dist_sq);
        if (dist > (self.boundary_radius - p.radius)) {
            if (dist == 0) return; // avoid div-by-zero

            const n = to / @as(Vec2, @splat(dist)); // outward normal
            // Project position onto circle surface (slightly inside to avoid jitter)
            p.position = self.boundary_center - n * @as(Vec2, @splat((self.boundary_radius - p.radius)));
        }
    }

    fn checkCollisions(self: *Self) void {
        const coeff: f32 = 1.15;
        for (0..self.particles.items.len) |i| {
            var p1 = &self.particles.items[i];
            for (i + 1..self.particles.items.len) |j| {
                var p2 = &self.particles.items[j];
                const v = p1.position - p2.position;
                const dist_sq = v[0] * v[0] + v[1] * v[1];
                const min_dist = p1.radius + p2.radius;
                if (dist_sq < min_dist * min_dist) {
                    const dist = @sqrt(dist_sq);
                    const n = v / @as(Vec2, @splat(dist));
                    const mr1 = p1.radius / (p1.radius + p2.radius);
                    const mr2 = p2.radius / (p1.radius + p2.radius);
                    const delta = 0.5 + coeff * (dist - min_dist);
                    p1.position -= n * @as(Vec2, @splat(mr2 * delta));
                    p2.position += n * @as(Vec2, @splat(mr1 * delta));
                }
            }
        }
    }
};
