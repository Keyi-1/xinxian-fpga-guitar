package com.keyi.xinxian.guitar;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.os.SystemClock;
import android.view.View;

/** Small decorative header only. No bitmap allocations or callbacks while off screen. */
public final class MusicBackdropView extends View {
    private final Paint paint = new Paint(3);
    private final Path path = new Path();
    private boolean enabled = true, active;
    private float frame;
    private final Runnable tick = () -> invalidate();

    public MusicBackdropView(Context context) {
        super(context);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        setClickable(false);
    }
    public void animateNotes(boolean value) { enabled = value; update(); }
    public void setActive(boolean value) { active = value; update(); }
    private void update() { removeCallbacks(tick); invalidate(); }
    private boolean moving() {
        return enabled && active && getWindowVisibility() == VISIBLE && isShown() && ValueAnimator.areAnimatorsEnabled();
    }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float density = getResources().getDisplayMetrics().density;
        float width = getWidth(), height = getHeight();
        if (moving()) frame = SystemClock.uptimeMillis() / 7000f;
        paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(density);
        for (int i = 0; i < 4; i++) {
            paint.setColor(i % 2 == 0 ? 0x2843d9ef : 0x289b8af9);
            float y = height * .36f + i * 8 * density;
            path.reset(); path.moveTo(width * .25f, y);
            path.cubicTo(width * .55f, y - 35 * density, width * .65f, y + 65 * density, width, y + 15 * density);
            canvas.drawPath(path, paint);
        }
        for (int i = 0; i < 12; i++) {
            float x = width * (.37f + ((i * 37) % 60) / 100f);
            float y = height * (.1f + ((i * 19) % 65) / 100f) + (float)Math.sin(frame + i * 1.7) * 5 * density;
            paint.setColor(i % 2 == 0 ? 0x6643d9ef : 0x669b8af9);
            paint.setStyle(Paint.Style.FILL);
            if (i % 4 != 0) canvas.drawCircle(x, y, density * 1.2f, paint);
            else {
                canvas.drawOval(x - 3*density, y, x + 2*density, y + 3*density, paint);
                paint.setStyle(Paint.Style.STROKE);
                canvas.drawLine(x + 2*density, y + density, x + 2*density, y - 9*density, paint);
                canvas.drawLine(x + 2*density, y - 9*density, x + 6*density, y - 5*density, paint);
            }
        }
        if (moving()) postDelayed(tick, 50);
    }
    @Override protected void onWindowVisibilityChanged(int visibility) { super.onWindowVisibilityChanged(visibility); update(); }
    @Override protected void onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow(); }
}
