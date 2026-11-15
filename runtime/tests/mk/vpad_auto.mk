# native-test-vpad_auto：「自动」按键布局（中间触屏）与触屏槽位读取（ios/vpad_layout.m / .h，Foundation 层，Mac 上编）
NATIVE_TEST_OWN += vpad_auto
.PHONY: native-test-vpad_auto
native-test-vpad_auto:
	@mkdir -p $(BUILD)/tests
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework CoreGraphics -o $(BUILD)/tests/t_vpad_auto runtime/tests/t_vpad_auto.m ios/vpad_layout.m
	$(BUILD)/tests/t_vpad_auto
TEST_TARGETS += native-test-vpad_auto
