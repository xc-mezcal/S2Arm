// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 S2Arm contributors
using S2A.Services;
using System;
using System.Collections.Generic;
using System.Linq;

namespace S2A.Services.Tests
{
    // 按键可见窗（InputPump.ButtonVisibility，个人补丁：松开可见窗 + 按下窗取 max(20 ms, 帧窗)）。
    //   模拟输入泵：手指变化或 Deadline 到点就跑一轮 Apply + Commit，记下写进 HID 的键位时间线；
    //   再按游戏「每帧只读一次最新状态」在各相位取样，数 A 的上升沿 = 游戏认到几下。
    //   期望手算（帧窗 34 ms，按下窗 34 ms）：
    //   ① 一指快速双击，按 0–30、松 30–45、按 45–90 ms：第一下撑到 34 松开，松开撑到 68，第二下 68 补发、撑到 102 → HID 上升沿 0、68；
    //      30 帧游戏任何相位都认 2 下。负对照（改前逻辑）：HID 上升沿 0、45，松开只有 15 ms，30 帧游戏有相位只认 1 下。
    //   ② 两下都极短，按 0–10、松 10–18、按 18–26 ms：第二下落在第一下的按下窗里，改前并成一下（上升沿只有 0）；
    //      改后按下窗过完 34 报松开，68 补发第二下 → 上升沿 0、68。
    //   ③ 慢双击，按 0–60、松 60–140、按 140–200 ms：两窗都不起作用，HID 与改前逐项相同（上升沿 0、140，不加延迟）。
    //   ④ 长按 0–200 ms：只一下，中间不插松开。
    static class InputReleaseWindowTest
    {
        // 改前的 ButtonVisibility 原样（负对照）：按下窗 20 ms，松开不撑
        private sealed class Legacy
        {
            private readonly ulong[] _until = new ulong[16];
            private uint _submitted, _next, _newlyPressed;
            public uint Apply(uint buttons, ulong now)
            {
                _newlyPressed = buttons & ~_submitted;
                _next = buttons;
                for (int bit = 0; bit < 16; bit++)
                    if ((_submitted & (1u << bit)) != 0 && now < _until[bit]) _next |= 1u << bit;
                return _next;
            }
            public void Commit(ulong t)
            {
                for (int bit = 0; bit < 16; bit++) if ((_newlyPressed & (1u << bit)) != 0) _until[bit] = t + 20_000;
                _submitted = _next;
            }
            public ulong Deadline(uint physical, ulong now, ulong heartbeat)
            {
                ulong d = heartbeat;
                for (int bit = 0; bit < 16; bit++)
                    if ((_submitted & ~physical & (1u << bit)) != 0 && _until[bit] < d) d = Math.Max(_until[bit], now);
                return d;
            }
        }

        private const uint A = 1;
        private const ulong End = 400_000;

        // 泵：事件驱动（手指一变就醒）+ Deadline + 16 ms 心跳，同 InputPump.Loop
        private static List<(ulong T, uint B)> Pump(Func<uint, ulong, uint> apply, Action<ulong> commit, Func<uint, ulong, ulong, ulong> deadline, (ulong T, uint B)[] events)
        {
            var hid = new List<(ulong, uint)>(); ulong t = 0; int k = 0; uint phys = 0;
            while (t <= End)
            {
                while (k < events.Length && events[k].T <= t) phys = events[k++].B;
                uint o = apply(phys, t); commit(t);
                if (hid.Count == 0 || hid[^1].Item2 != o) hid.Add((t, o));
                ulong next = deadline(phys, t, t + 16_000);
                if (k < events.Length) next = Math.Min(next, events[k].T);
                t = Math.Max(next, t + 1);
            }
            return hid;
        }
        private static List<(ulong, uint)> RunNew((ulong, uint)[] ev)
        {
            var v = new InputPump.ButtonVisibility(34_000);
            return Pump((b, n) => v.Apply(b, 0, 0, n), v.Commit, v.Deadline, ev);
        }
        private static List<(ulong, uint)> RunOld((ulong, uint)[] ev)
        {
            var v = new Legacy();
            return Pump(v.Apply, v.Commit, v.Deadline, ev);
        }
        private static string Rises(List<(ulong T, uint B)> hid)
        {
            var r = new List<ulong>(); uint last = 0;
            foreach (var (t, b) in hid) { if ((b & A) != 0 && (last & A) == 0) r.Add(t / 1000); last = b; }
            return string.Join("、", r);
        }
        // 游戏每 period 读一次最新状态；返回所有相位里最少认到几下
        private static int WorstPresses(List<(ulong T, uint B)> hid, ulong period)
        {
            int worst = int.MaxValue;
            for (ulong phase = 0; phase < period; phase += 1000)
            {
                int n = 0; uint last = 0;
                for (ulong f = phase; f < End; f += period)
                {
                    uint cur = 0; foreach (var (t, b) in hid) if (t <= f) cur = b; else break;
                    if ((cur & A) != 0 && (last & A) == 0) n++;
                    last = cur;
                }
                worst = Math.Min(worst, n);
            }
            return worst;
        }

        [SoloTest("--input-release-window")]
        private static int Run()
        {
            var fast = new (ulong, uint)[] { (0, A), (30_000, 0), (45_000, A), (90_000, 0) };
            var tiny = new (ulong, uint)[] { (0, A), (10_000, 0), (18_000, A), (26_000, 0) };
            var slow = new (ulong, uint)[] { (0, A), (60_000, 0), (140_000, A), (200_000, 0) };
            var hold = new (ulong, uint)[] { (0, A), (200_000, 0) };
            var rows = new List<(string Name, string Expect, string Actual)>
            {
                ("① 快速双击 HID 上升沿（ms）", "0、68", Rises(RunNew(fast))),
                ("① 快速双击 30 帧游戏最少认到", "2", WorstPresses(RunNew(fast), 33_333).ToString()),
                ("① 负对照（改前）HID 上升沿", "0、45", Rises(RunOld(fast))),
                ("① 负对照（改前）30 帧游戏最少认到", "1", WorstPresses(RunOld(fast), 33_333).ToString()),
                ("② 两下极短 HID 上升沿", "0、68", Rises(RunNew(tiny))),
                ("② 负对照（改前）HID 上升沿", "0", Rises(RunOld(tiny))),
                ("③ 慢双击 HID 时间线与改前相同", "True", RunNew(slow).SequenceEqual(RunOld(slow)).ToString()),
                ("③ 慢双击 HID 上升沿", "0、140", Rises(RunNew(slow))),
                ("④ 长按 HID 上升沿", "0", Rises(RunNew(hold))),
                ("④ 长按 HID 时间线条数（按下 + 松开）", "2", RunNew(hold).Count.ToString()),
            };
            int bad = 0;
            foreach (var (name, expect, actual) in rows)
            {
                bool ok = expect == actual; if (!ok) bad++;
                Console.WriteLine($"{(ok ? "✓" : "✗")} {name}：{expect} → {actual}");
            }
            return bad == 0 ? 0 : 1;
        }
    }
}
