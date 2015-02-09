//
//  StreamDataSource.swift
//  Ello
//
//  Created by Sean Dougherty on 11/22/14.
//  Copyright (c) 2014 Ello. All rights reserved.
//

import UIKit
import WebKit

class StreamDataSource: NSObject, UICollectionViewDataSource {

    typealias StreamContentReady = (indexPaths:[NSIndexPath]) -> ()

    let testWebView:UIWebView
    let streamKind:StreamKind

    var indexFile:String?
    var streamCellItems:[StreamCellItem] = []
    let sizeCalculator:StreamTextCellSizeCalculator
    weak var postbarDelegate:PostbarDelegate?
    weak var webLinkDelegate:WebLinkDelegate?
    weak var imageDelegate:StreamImageCellDelegate?
    weak var userDelegate:UserDelegate?

    init(testWebView: UIWebView, streamKind:StreamKind) {
        self.streamKind = streamKind
        self.testWebView = testWebView
        self.sizeCalculator = StreamTextCellSizeCalculator(webView: testWebView)
        super.init()
    }

    // MARK: - Public

    func postForIndexPath(indexPath:NSIndexPath) -> Post? {
        if indexPath.item >= streamCellItems.count {
            return nil
        }
        return streamCellItems[indexPath.item].streamable as? Post
    }

    // TODO: also grab out comment cells for the detail view
    func cellItemsForPost(post:Post) -> [StreamCellItem] {
        return streamCellItems.filter({ (item) -> Bool in
            if let cellPost = item.streamable as? Post {
                return post.postId == cellPost.postId
            }
            else {
                return false
            }
        })
    }

    func commentIndexPathsForPost(post: Post) -> [NSIndexPath] {
        var indexPaths:[NSIndexPath] = []

        for (index,value) in enumerate(streamCellItems) {

            if let comment = value.streamable as? Comment {
                if comment.parentPost?.postId == post.postId {
                    indexPaths.append(NSIndexPath(forItem: index, inSection: 0))
                }
            }
        }
        return indexPaths
    }

    func addStreamCellItems(items:[StreamCellItem]) {
        self.streamCellItems += items
    }

    func addStreamables(streamables:[Streamable], startingIndexPath:NSIndexPath?, completion:StreamContentReady) {
        self.createStreamCellItems(streamables, startingIndexPath: startingIndexPath, completion: completion)
    }

    func updateHeightForIndexPath(indexPath:NSIndexPath?, height:CGFloat) {
        if let indexPath = indexPath {
            streamCellItems[indexPath.item].oneColumnCellHeight = height
            streamCellItems[indexPath.item].multiColumnCellHeight = height
        }
    }

    func heightForIndexPath(indexPath:NSIndexPath, numberOfColumns:NSInteger) -> CGFloat {
        if numberOfColumns == 1 {
            return streamCellItems[indexPath.item].oneColumnCellHeight ?? 0.0
        }
        else {
            return streamCellItems[indexPath.item].multiColumnCellHeight ?? 0.0
        }
    }

    func maintainAspectRatioForItemAtIndexPath(indexPath:NSIndexPath) -> Bool {
        return streamCellItems[indexPath.item].data?.kind == Block.Kind.Image ?? false
    }

    func groupForIndexPath(indexPath:NSIndexPath) -> String {
        return streamCellItems[indexPath.item].streamable.groupId
    }

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return streamCellItems.count ?? 0
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if indexPath.item < countElements(streamCellItems) {
            let streamCellItem = streamCellItems[indexPath.item]

            switch streamCellItem.type {
            case .Header, .CommentHeader:
                return headerCell(streamCellItem, collectionView: collectionView, indexPath: indexPath)
            case .BodyElement, .CommentBodyElement:
                return bodyCell(streamCellItem, collectionView: collectionView, indexPath: indexPath)
            case .Footer:
                return footerCell(streamCellItem, collectionView: collectionView, indexPath: indexPath)
            default:
                return UICollectionViewCell()
            }
        }

        return UICollectionViewCell()
    }

    // MARK: - Private

    private func headerCell(streamCellItem:StreamCellItem, collectionView: UICollectionView, indexPath: NSIndexPath) -> UICollectionViewCell {

        var headerCell:StreamHeaderCell
        switch streamCellItem.streamable.kind {
        case .Comment:
            headerCell = collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.CommentHeader.name, forIndexPath: indexPath) as StreamCommentHeaderCell
        default:
            headerCell = collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.Header.name, forIndexPath: indexPath) as StreamHeaderCell
            headerCell.streamKind = streamKind
        }

        if let avatarURL = streamCellItem.streamable.author?.avatarURL? {
            headerCell.setAvatarURL(avatarURL)
        }

        headerCell.timestampLabel.text = NSDate().distanceOfTimeInWords(streamCellItem.streamable.createdAt)
        headerCell.usernameLabel.text = (streamCellItem.streamable.author?.atName ?? "@meow")
        headerCell.userDelegate = userDelegate
        return headerCell
    }

    private func bodyCell(streamCellItem:StreamCellItem, collectionView: UICollectionView, indexPath: NSIndexPath) -> UICollectionViewCell {

        switch streamCellItem.data!.kind {
        case Block.Kind.Image:
            return imageCell(streamCellItem, collectionView: collectionView, indexPath: indexPath)
        case Block.Kind.Text:
            return textCell(streamCellItem, collectionView: collectionView, indexPath: indexPath)
        case Block.Kind.Unknown:
            return collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.Unknown.name, forIndexPath: indexPath) as UICollectionViewCell
        }
    }

    private func imageCell(streamCellItem:StreamCellItem, collectionView: UICollectionView, indexPath: NSIndexPath) -> StreamImageCell {
        let imageCell = collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.Image.name, forIndexPath: indexPath) as StreamImageCell

        if let photoData = streamCellItem.data as ImageBlock? {
            if let photoURL = photoData.hdpi?.url? {
                imageCell.serverProvidedAspectRatio = StreamCellItemParser.aspectRatioForImageBlock(photoData)
                imageCell.setImageURL(photoURL)
            }
            else if let photoURL = photoData.url? {
                imageCell.setImageURL(photoURL)
            }
        }

        imageCell.delegate = imageDelegate
        return imageCell
    }

    private func textCell(streamCellItem:StreamCellItem, collectionView: UICollectionView, indexPath: NSIndexPath) -> StreamTextCell {
        var textCell:StreamTextCell = collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.Text.name, forIndexPath: indexPath) as StreamTextCell

        textCell.contentView.alpha = 0.0
        if let textData = streamCellItem.data as TextBlock? {
            textCell.webView.loadHTMLString(StreamTextCellHTML.postHTML(textData.content), baseURL: NSURL(string: "/"))
        }

        if let comment = streamCellItem.streamable as? Comment {
            textCell.leadingConstraint.constant = 58.0
        }
        else {
            textCell.leadingConstraint.constant = 0.0
        }
        
        textCell.webLinkDelegate = webLinkDelegate
        return textCell
    }

    private func footerCell(streamCellItem:StreamCellItem, collectionView: UICollectionView, indexPath: NSIndexPath) -> StreamFooterCell {
        let footerCell = collectionView.dequeueReusableCellWithReuseIdentifier(StreamCellType.Footer.name, forIndexPath: indexPath) as StreamFooterCell
        if let post = streamCellItem.streamable as? Post {
            footerCell.comments = post.commentsCount?.localizedStringFromNumber()
            if self.streamKind.isGridLayout {
                footerCell.views = ""
                footerCell.reposts = ""
            }
            else {
                footerCell.views = post.viewsCount?.localizedStringFromNumber()
                footerCell.reposts = post.repostsCount?.localizedStringFromNumber()
            }
            footerCell.streamKind = streamKind
            footerCell.delegate = postbarDelegate
        }

        return footerCell
    }

    private func createStreamCellItems(streamables:[Streamable], startingIndexPath:NSIndexPath?, completion:StreamContentReady) {
        var cellItems = StreamCellItemParser().streamCellItems(streamables)

        let textElements = cellItems.filter {
            return $0.data as? TextBlock != nil
        }

        self.sizeCalculator.processCells(textElements) {
            var indexPaths:[NSIndexPath] = []

            var indexPath:NSIndexPath = startingIndexPath ?? NSIndexPath(forItem: countElements(self.streamCellItems) - 1, inSection: 0)

            for (index, cellItem) in enumerate(cellItems) {
                var index = indexPath.item + index + 1
                indexPaths.append(NSIndexPath(forItem: index, inSection: 0))
                self.streamCellItems.insert(cellItem, atIndex: index)
            }

            completion(indexPaths: indexPaths)
        }
   }
}
