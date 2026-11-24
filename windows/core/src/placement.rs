//! Where the picker window goes: at the mouse, kept within the monitor's work area.
//! Screen coordinates in physical pixels, origin top-left (Windows).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

/// Margin to the work area's edge, and the offset of the window's top-left corner from the
/// mouse (left of and above it, so the first row sits under the pointer), in logical pixels.
const INSET: f64 = 8.0;
const MOUSE_OFFSET: (f64, f64) = (24.0, 12.0);

/// Top-left corner for a window of `size` that opens at `mouse`, kept inside `work_area`. A window
/// too big for the screen keeps its top-left corner on screen, where the links and the first
/// targets are.
pub fn origin(mouse: (i32, i32), size: (i32, i32), work_area: Rect, scale: f64) -> (i32, i32) {
    let inset = (INSET * scale).round() as i32;
    let x = mouse.0 - (MOUSE_OFFSET.0 * scale).round() as i32;
    let y = mouse.1 - (MOUSE_OFFSET.1 * scale).round() as i32;
    let max_x = work_area.x + work_area.width - size.0 - inset;
    let max_y = work_area.y + work_area.height - size.1 - inset;
    let x = x.min(max_x).max(work_area.x + inset);
    let y = y.min(max_y).max(work_area.y + inset);
    (x, y)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: Rect = Rect { x: 0, y: 0, width: 1920, height: 1040 };

    #[test]
    fn opens_up_left_of_the_mouse() {
        assert_eq!(origin((500, 400), (360, 300), SCREEN, 1.0), (476, 388));
        assert_eq!(origin((500, 400), (360, 300), SCREEN, 2.0), (452, 376));
    }

    #[test]
    fn stays_inside_the_work_area() {
        assert_eq!(origin((1910, 1030), (360, 300), SCREEN, 1.0), (1552, 732));
        assert_eq!(origin((2, 2), (360, 300), SCREEN, 1.0), (8, 8));
        // second monitor left of the primary
        let left = Rect { x: -1920, y: 0, width: 1920, height: 1040 };
        assert_eq!(origin((-10, 500), (360, 300), left, 1.0), (-368, 488));
        // taller than the screen: top stays visible
        assert_eq!(origin((500, 900), (360, 2000), SCREEN, 1.0).1, 8);
    }
}
