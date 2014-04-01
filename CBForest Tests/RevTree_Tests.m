//
//  RevTree_Tests.m
//  CBForest
//
//  Created by Jens Alfke on 3/28/14.
//  Copyright (c) 2014 Couchbase. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "rev_tree.h"
#import "varint.h"


static sized_buf strtobuf(const char* str) {return (sized_buf){(void*)str, strlen(str)};}
static bool bufequalstr(sized_buf buf, const char* str) {
    return buf.size == strlen(str) && memcmp(buf.buf, str, buf.size) == 0;
}


@interface RevTree_Tests : XCTestCase
@end


@implementation RevTree_Tests
{
    RevTree* tree;
}

- (void) setUp {
    [super setUp];
}

- (void) tearDown {
    RevTreeFree(tree);
    tree = nil;
    [super tearDown];
}

- (void) testVarint {
    const uint64_t tests[] = {0, 1, 127, 128, 123456, 0x12345678, 0x1234567812345678,
        0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF};
    uint8_t buf[kMaxVarintLen64];
    for (int i=0; i<9; i++) {
        size_t len = WriteUVarInt(buf, tests[i]);
        XCTAssert(len > 0 && len <= kMaxVarintLen64);
        XCTAssertEqual(len, SizeOfVarInt(tests[i]));
        uint64_t readNum;
        size_t readLen = ReadUVarInt((sized_buf){buf, len}, &readNum);
        XCTAssertEqual(readLen, len);
        XCTAssertEqual(readNum, tests[i]);
    }
}

- (void) testParseRevID {
    unsigned sequence;
    sized_buf digest;
    XCTAssert(RevIDParse(strtobuf("42-cafebabe"), &sequence, &digest));
    XCTAssertEqual(sequence, 42);
    XCTAssert(bufequalstr(digest, "cafebabe"));

    XCTAssert(!RevIDParse(strtobuf(""), &sequence, &digest));
    XCTAssert(!RevIDParse(strtobuf("0-cafebabe"), &sequence, &digest));
    XCTAssert(!RevIDParse(strtobuf("-cafebabe"), &sequence, &digest));
    XCTAssert(!RevIDParse(strtobuf("10-"), &sequence, &digest));
    XCTAssert(!RevIDParse(strtobuf("111111111111111-foo"), &sequence, &digest));
    XCTAssert(!RevIDParse(strtobuf("1af9-decafbad"), &sequence, &digest));
}

- (void) testNewTree {
    tree = RevTreeNew(1);
    XCTAssert(tree != nil);
    XCTAssertEqual(RevTreeGetCount(tree), 0);
    XCTAssertEqual(RevTreeGetCurrentNode(tree), NULL);
    XCTAssertEqual(RevTreeGetNode(tree, 0), NULL);
    XCTAssertEqual(RevTreeFindNode(tree, strtobuf("1-deadbeef")), NULL);
    XCTAssert(!RevTreeHasConflict(tree));
}

- (void) testInsertRev {
    // Create a tree and insert a revision:
    tree = RevTreeNew(1);
    RevTreeInsert(&tree, strtobuf("1-f00"), strtobuf("{\"hi\":true}"), (sized_buf){}, false, 0);
    XCTAssertEqual(RevTreeGetCount(tree), 1);
    const RevNode* node = RevTreeGetNode(tree, 0);
    XCTAssert(node != nil);
    XCTAssert(bufequalstr(node->revID, "1-f00"));
    XCTAssert(bufequalstr(node->data, "{\"hi\":true}"));
    XCTAssertEqual(node->parentIndex, kRevNodeParentIndexNone);
    XCTAssertEqual(node->flags, kRevNodeIsLeaf);

    XCTAssertEqual(RevTreeGetNode(tree, 1), NULL);
    XCTAssertEqual(RevTreeGetCurrentNode(tree), node);
    XCTAssertEqual(RevTreeFindNode(tree, strtobuf("1-f00")), node);
    XCTAssertEqual(RevTreeFindNode(tree, strtobuf("1-deadbeef")), NULL);
    XCTAssert(!RevTreeHasConflict(tree));

    // Reserve capacity. This will realloc the tree:
    RevTreeReserveCapacity(&tree, 1);
    XCTAssertEqual(RevTreeGetCount(tree), 1);
    node = RevTreeGetNode(tree, 0);
    XCTAssert(node != nil);
    XCTAssert(bufequalstr(node->revID, "1-f00"));

    // Insert a new revision:
    RevTreeInsert(&tree, strtobuf("2-ba4"), strtobuf("{\"hi\":false}"), node->revID, false, 0);
    XCTAssertEqual(RevTreeGetCount(tree), 2);
    const RevNode* node2 = RevTreeGetNode(tree, 1);
    XCTAssert(node2 != nil);
    XCTAssert(bufequalstr(node2->revID, "2-ba4"));
    XCTAssert(bufequalstr(node2->data, "{\"hi\":false}"));
    XCTAssertEqual(node2->parentIndex, 0);
    XCTAssertEqual(node2->flags, kRevNodeIsLeaf);
    XCTAssertEqual(node->flags, 0);

    // Sort the revisions: this will change their order:
    RevTreeSort(tree);
    node = RevTreeFindNode(tree, strtobuf("1-f00"));
    XCTAssertEqual(node, RevTreeGetNode(tree, 1));
    XCTAssertEqual(node->parentIndex, kRevNodeParentIndexNone);
    node2 = RevTreeFindNode(tree, strtobuf("2-ba4"));
    XCTAssertEqual(node2, RevTreeGetNode(tree, 0));
    XCTAssertEqual(node2->parentIndex, 1);
}

@end
