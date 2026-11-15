// 「自动」按键布局（ios/vpad_layout.m +autoForSafeRect:split: / builtinForIdentifier / passesUnclaimedTouches）
//   与触屏槽位读取（ios/vpad_layout.h S2AVPadTouchSlotRead）。期望手写：
//   ① auto 是内置 id；builtinForIdentifier：auto → auto、2d → 2d、default / touch / nil → default
//   ② auto 的按键与默认布局逐个相同（同一块安全区）
//   ③ auto 摇杆激活区：左 [0, 0.35)、右 [0.65, 1]；中间一点（0.5w, 0.6h）两边都不在、也没按到键 → 有空地给触屏
//   ④ 负对照：默认布局同一点落在右摇杆激活区（半屏）→ 没有空地，这就是旧布局点不了屏幕的原因
//   ⑤ passesUnclaimedTouches：auto YES；default / 2d NO
//   ⑥ 分屏（split）的 auto 同样收窄激活区
//   ⑦ store：选 auto → 重开仍是 auto；auto → 切触 → 切回 = auto（.last_keys 记得 auto）
//   ⑧ 槽位读取：按住 → Start、0、0，抬手 → End，再读 → 不出
//   ⑨ 快速点按（按下、抬手都在两次读取之间）→ 先 Start、下一拍 End（旧实现只发一拍 End，游戏读不到按下）
//   旧实现没有 autoForSafeRect / S2AVPadTouchSlotRead：编不过（红）
#import <Foundation/Foundation.h>
#import "../../ios/vpad_layout.h"
static int bad;
#define CK(c, ...) do { if (c) printf("✓ " __VA_ARGS__); else { printf("✗ " __VA_ARGS__); bad++; } printf("\n"); } while (0)
static CGRect act(S2AVPadLayout *l, NSString *side, CGRect safe) {
    for (NSDictionary *s in l.sticks) if ([s[@"id"] isEqualToString:side]) return [l activationForStick:s safeRect:safe];
    return CGRectNull;
}
int main(void) { @autoreleasepool {
    CGRect safe = CGRectMake(0, 0, 832, 419);
    S2AVPadLayout *a = [S2AVPadLayout autoForSafeRect:safe split:NO], *d = [S2AVPadLayout defaultForSafeRect:safe split:NO];
    S2AVPadLayout *b1 = [S2AVPadLayout builtinForIdentifier:S2AVPadLayoutAutoIdentifier safeRect:safe split:NO];
    S2AVPadLayout *b2 = [S2AVPadLayout builtinForIdentifier:S2AVPadLayout2DIdentifier safeRect:safe split:NO];
    S2AVPadLayout *b3 = [S2AVPadLayout builtinForIdentifier:S2AVPadLayoutTouchIdentifier safeRect:safe split:NO];
    S2AVPadLayout *b4 = [S2AVPadLayout builtinForIdentifier:nil safeRect:safe split:NO];
    CK([S2AVPadLayout isBuiltinIdentifier:@"auto"] && [b1.identifier isEqualToString:@"auto"] && [b2.identifier isEqualToString:@"2d"]
       && [b3.identifier isEqualToString:@"default"] && [b4.identifier isEqualToString:@"default"],
       "① auto 内置；builtinForIdentifier 映射（实得 %s %s %s %s）", b1.identifier.UTF8String, b2.identifier.UTF8String, b3.identifier.UTF8String, b4.identifier.UTF8String);
    CK([a.buttons isEqualToArray:d.buttons], "② auto 按键与默认布局逐个相同（%lu / %lu 个）", (unsigned long)a.buttons.count, (unsigned long)d.buttons.count);
    CGRect l = act(a, @"left", safe), r = act(a, @"right", safe); CGPoint mid = CGPointMake(0.5 * safe.size.width, 0.6 * safe.size.height);
    BOOL inStick = CGRectContainsPoint(l, mid) || CGRectContainsPoint(r, mid); NSString *key = [a buttonAt:mid safeRect:safe slop:10];
    CK(fabs(CGRectGetMaxX(l) - 0.35 * 832) < 0.5 && fabs(CGRectGetMinX(r) - 0.65 * 832) < 0.5 && fabs(CGRectGetMaxX(r) - 832) < 0.5 && !inStick && !key,
       "③ auto 激活区 左到 %.1f、右从 %.1f 到 %.1f；中点在摇杆区 %d、按到键 %s", CGRectGetMaxX(l), CGRectGetMinX(r), CGRectGetMaxX(r), inStick, key.UTF8String ?: "无");
    BOOL dIn = CGRectContainsPoint(act(d, @"left", safe), mid) || CGRectContainsPoint(act(d, @"right", safe), mid);
    CK(dIn, "④ 负对照：默认布局同一点在摇杆激活区（实得 %d）", dIn);
    CK(a.passesUnclaimedTouches && !d.passesUnclaimedTouches && !b2.passesUnclaimedTouches, "⑤ passesUnclaimedTouches：auto %d default %d 2d %d",
       a.passesUnclaimedTouches, d.passesUnclaimedTouches, b2.passesUnclaimedTouches);
    S2AVPadLayout *as = [S2AVPadLayout autoForSafeRect:CGRectMake(0, 0, 600, 360) split:YES];
    CGRect sl = act(as, @"left", CGRectMake(0, 0, 600, 360)), sr = act(as, @"right", CGRectMake(0, 0, 600, 360));
    CK(fabs(sl.size.width - 210) < 0.5 && fabs(sr.origin.x - 390) < 0.5, "⑥ 分屏 auto 激活区 左宽 %.1f、右起 %.1f", sl.size.width, sr.origin.x);

    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES]; NSError *e;
    S2AVPadLayoutStore *s = [[S2AVPadLayoutStore alloc] initWithDirectory:dir];
    BOOL sel = [s selectIdentifier:S2AVPadLayoutAutoIdentifier error:&e];
    S2AVPadLayoutStore *s2 = [[S2AVPadLayoutStore alloc] initWithDirectory:dir]; NSString *reopened = [s2.selectedIdentifier copy];
    int on = [s2 setTouchOnly:YES error:&e], off = [s2 setTouchOnly:NO error:&e];
    CK(sel && [reopened isEqualToString:@"auto"] && on == 1 && off == 1 && [s2.selectedIdentifier isEqualToString:@"auto"],
       "⑦ 选 auto 持久化；auto → 触 → 回 auto（实得 选 %d 重开 %s 切 %d %d 现 %s；%s）", sel, reopened.UTF8String, on, off, s2.selectedIdentifier.UTF8String, e.localizedDescription.UTF8String ?: "");
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];

    uint8_t st = 1; BOOL start = YES; int r1 = S2AVPadTouchSlotRead(&st, &start), r2 = S2AVPadTouchSlotRead(&st, &start), r3 = S2AVPadTouchSlotRead(&st, &start);
    st = 2; int r4 = S2AVPadTouchSlotRead(&st, &start), r5 = S2AVPadTouchSlotRead(&st, &start);
    CK(r1 == 1 && r2 == 0 && r3 == 0 && r4 == 2 && r5 == -1, "⑧ 按住：Start 0 0、抬手 End、再读不出（实得 %d %d %d %d %d）", r1, r2, r3, r4, r5);
    st = 2; start = YES; int t1 = S2AVPadTouchSlotRead(&st, &start), t2 = S2AVPadTouchSlotRead(&st, &start), t3 = S2AVPadTouchSlotRead(&st, &start);
    CK(t1 == 1 && t2 == 2 && t3 == -1, "⑨ 快速点按：Start、End、不出（实得 %d %d %d）", t1, t2, t3);

    if (bad) printf("t_vpad_auto：%d 项不过\n", bad); else printf("✓ t_vpad_auto：9 项（内置映射 / 按键同默认 / 中间空地 / 默认负对照 / 透传标记 / 分屏 / 持久化与切回 / 槽位读取 / 快速点按）\n");
    return bad ? 1 : 0;
} }
