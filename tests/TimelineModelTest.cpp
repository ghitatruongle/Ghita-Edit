#include "timeline/TimelineModel.h"
#include <gtest/gtest.h>

using ghita::timeline::TimelineModel;

TEST(TimelineModelTest, addClipTracksRows) {
    TimelineModel m;
    m.addClip("a.mp4", 0, 1000, 0, 0);   // video V1
    m.addClip("a.mp4", 0, 1000, 1000, 1); // audio A1
    EXPECT_EQ(m.rowCount(), 2);
    EXPECT_EQ(m.clipStartMs(0), 0);
    EXPECT_EQ(m.clipEndMs(0), 1000);
    EXPECT_EQ(m.clipStartMs(1), 1000);
}

TEST(TimelineModelTest, splitAtPlayheadCreatesTwo) {
    TimelineModel m;
    m.addClip("a.mp4", 0, 1000, 0, 0);
    m.setPlayheadMs(400);
    m.splitClipAtPlayhead(m.clipId(0));
    EXPECT_EQ(m.rowCount(), 2);
    EXPECT_EQ(m.clipEndMs(0), 400);
    EXPECT_EQ(m.clipStartMs(1), 400);
}

TEST(TimelineModelTest, undoRedoRestoresState) {
    TimelineModel m;
    m.addClip("a.mp4", 0, 1000, 0, 0);
    m.setPlayheadMs(400);
    m.splitClipAtPlayhead(m.clipId(0));
    EXPECT_EQ(m.rowCount(), 2);
    m.undo();
    EXPECT_EQ(m.rowCount(), 1);
    m.redo();
    EXPECT_EQ(m.rowCount(), 2);
}

TEST(TimelineModelTest, deleteClip) {
    TimelineModel m;
    m.addClip("a.mp4", 0, 1000, 0, 0);
    m.deleteClip(m.clipId(0));
    EXPECT_EQ(m.rowCount(), 0);
}
