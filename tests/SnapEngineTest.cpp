#include "timeline/SnapEngine.h"
#include <gtest/gtest.h>

using ghita::timeline::SnapEngine;

TEST(SnapEngineTest, snapsWithinThreshold) {
    SnapEngine e;
    e.setThresholdMs(10);
    // target at 100; candidate 106 is within 10 ms -> snaps to 100
    QVariantList targets = {QVariant(100)};
    EXPECT_EQ(e.snap(106, targets), 100);
}

TEST(SnapEngineTest, leavesAloneOutsideThreshold) {
    SnapEngine e;
    e.setThresholdMs(10);
    QVariantList targets = {QVariant(100)};
    EXPECT_EQ(e.snap(130, targets), 130); // 30 ms away -> unchanged
}

TEST(SnapEngineTest, picksNearestTarget) {
    SnapEngine e;
    e.setThresholdMs(15);
    QVariantList targets = {QVariant(100), QVariant(200)};
    EXPECT_EQ(e.snap(112, targets), 100);
    EXPECT_EQ(e.snap(188, targets), 200);
}
