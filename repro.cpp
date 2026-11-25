// Asks, at compile time, whether the TextLayoutManager of ReactCommon's cxx platform (the one Fantom's tester builds and
// subclasses) measures lines, as ParagraphShadowNode::baseline and onTextLayout ask before they measure a Text's lines.
#include <react/renderer/textlayoutmanager/TextLayoutManagerExtended.h>

static_assert(facebook::react::TextLayoutManagerExtended::supportsLineMeasurement());
