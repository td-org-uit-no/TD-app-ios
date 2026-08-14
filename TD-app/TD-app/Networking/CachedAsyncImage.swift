import Combine
import SwiftUI
import UIKit

/// Shared image cache.
///
/// `AsyncImage` performs no caching of its own: every time a row scrolls out of
/// a `LazyVStack` and back in, its view is destroyed and the image is fetched
/// again from the network. With full-resolution event posters (up to ~280 KB
/// each) that leaves rows visibly blank until the download lands, which reads
/// as content "not showing up until you scroll past it".
///
/// This store keeps decoded images in memory and lets `URLSession`'s shared
/// `URLCache` handle the on-disk layer, so a row that has been seen once
/// renders instantly on every subsequent appearance.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    /// Incremented on every `invalidateAll()`. Views key their load task on it
    /// so they re-fetch when an image is replaced at an unchanged URL.
    private(set) static var generation = 0

    private static let invalidationSubject = PassthroughSubject<Int, Never>()

    /// Fires the new generation after a global invalidation.
    ///
    /// Main-actor isolated, like the subject behind it: `PassthroughSubject` is
    /// not `Sendable`, and the only consumer is `CachedAsyncImage.body`'s
    /// `.onReceive`, which is already on the main actor.
    static var invalidationPublisher: AnyPublisher<Int, Never> {
        invalidationSubject.eraseToAnyPublisher()
    }

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 150
        // Images are downsampled to `maxPixelSize` before they land here, so a
        // worst-case entry is ~4 MB rather than the ~6 MB a full-size poster
        // cost. 24 MB holds the whole event and job list at the sizes actually
        // drawn; the OS evicts under pressure anyway.
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// URLs that recently 404'd, with the time we learned that, so we don't
    /// re-request a missing image on every appearance. The API returns 404 for
    /// events and jobs with no uploaded picture.
    ///
    /// These expire: a picture uploaded while the app is running would
    /// otherwise stay invisible until the process restarted, since this cache
    /// only lives in memory. `missingTTL` is the window in which a listing that
    /// gained an image still shows as blank — short enough that a
    /// pull-to-refresh a moment later picks it up, long enough that scrolling a
    /// list of imageless rows doesn't re-hit the network for each one.
    private var missing: [URL: Date] = [:]

    private let missingTTL: TimeInterval = 60

    /// Whether `url` 404'd recently enough that we should not ask again yet.
    private func isMissingFresh(_ url: URL, now: Date = .now) -> Bool {
        guard let recordedAt = missing[url] else { return false }
        guard now.timeIntervalSince(recordedAt) < missingTTL else {
            // Expired — drop it so the entry doesn't linger for a URL that
            // may now resolve.
            missing[url] = nil
            return false
        }
        return true
    }

    /// In-flight requests, so several rows asking for the same URL share one
    /// download instead of racing.
    private var loads: [URL: Task<UIImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // `.useProtocolCachePolicy`, not `.returnCacheDataElseLoad`: an image
        // lives at a fixed URL (`/{id}/image`), so replacing a listing's picture
        // changes the bytes but not the address. `.returnCacheDataElseLoad`
        // serves any cached copy regardless of freshness and never asks the
        // server, which left a replaced image stale until the cache was cleared.
        // The protocol policy revalidates with the ETag the API already sends,
        // so an unchanged image costs a 304 and a changed one arrives.
        config.requestCachePolicy = .useProtocolCachePolicy
        // A small memory tier on purpose. This layer holds the *compressed*
        // bytes, and anything it would serve has already been decoded into
        // `cache` above — so a large in-memory URLCache mostly duplicates, in a
        // second copy, images the decoded cache is already holding. The disk
        // tier is what actually earns its keep across launches.
        config.urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "td-images"
        )
        return URLSession(configuration: config)
    }()

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func isKnownMissing(_ url: URL) -> Bool {
        isMissingFresh(url)
    }

    /// Forgets everything we know about `url` so the next request re-fetches.
    ///
    /// Needed because a listing's image URL is derived from its id alone: when
    /// a picture is replaced the address stays the same, so nothing else would
    /// tell the caches that the bytes moved on. Clears the decoded bitmap, the
    /// stored HTTP response, and any negative-cache entry.
    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
        missing[url] = nil
        session.configuration.urlCache?.removeCachedResponse(
            for: URLRequest(url: url)
        )
    }

    /// Re-checks every image against the server. Used on pull-to-refresh, where
    /// the intent is "show me what the server has now".
    ///
    /// The stored HTTP responses are deliberately *kept*. They carry the ETags
    /// the revalidation needs: clearing them, as this used to, left nothing to
    /// make a conditional request with, so every visible row re-downloaded and
    /// re-decoded its full poster on each pull-to-refresh. Bumping the
    /// generation alone already forces each view to ask again, and
    /// `revalidatingLoad` turns that into a conditional request — so an
    /// unchanged image now genuinely costs a 304, which is what the previous
    /// comment here claimed but the implementation did not deliver.
    ///
    /// The decoded bitmaps are dropped because a 304 refills them from the
    /// stored response, and the negative cache is cleared so a listing that
    /// gained a picture shows it immediately rather than waiting out `missingTTL`.
    func invalidateAll() {
        cache.removeAllObjects()
        missing.removeAll()
        Self.generation &+= 1
        Self.invalidationSubject.send(Self.generation)
    }

    /// Fetches `url`, serving the decoded cache when it can.
    ///
    /// `revalidate` forces the request past the HTTP cache's freshness check so
    /// the server is actually asked. It is set only after `invalidateAll()`,
    /// where the point is to notice a replaced image: the stored response is
    /// kept for its ETag, so this is a conditional request that answers 304 and
    /// costs no image bytes when nothing changed. Ordinary scrolling leaves it
    /// false and is served from cache without touching the network.
    func image(for url: URL, revalidate: Bool = false) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if isMissingFresh(url) { return nil }
        if let existing = loads[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [session] in
            do {
                var request = URLRequest(url: url)
                if revalidate {
                    // Revalidate with the server rather than trusting the
                    // cached copy's freshness; the stored ETag makes this a
                    // 304 when the image is unchanged.
                    request.cachePolicy = .reloadRevalidatingCacheData
                }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else { return nil }
                // Decoding happens off the main actor: `UIImage(data:)` only
                // stores the bytes, but the first draw decodes them on whatever
                // thread SwiftUI is drawing on — the main one. Downsampling here
                // moves that cost off the critical path and, more importantly,
                // caps what the decoded bitmap can cost.
                return Self.downsampledImage(from: data)
            } catch {
                return nil
            }
        }
        loads[url] = task

        let image = await task.value
        loads[url] = nil

        if let image {
            // `size` is in points; the bitmap behind it is `scale`× that in each
            // dimension, so costing by points alone understates a 3x image by 9.
            let pixels = image.size.width * image.size.height
                * image.scale * image.scale
            cache.setObject(image, forKey: url as NSURL, cost: Int(pixels) * 4)
        } else {
            missing[url] = .now
        }
        return image
    }

    /// The longest edge, in pixels, we keep a downloaded image at.
    ///
    /// Every image the app shows is either a thumbnail (64pt in the event list,
    /// 56pt on a job card) or the event detail banner, which is capped at 260pt
    /// tall and the screen's width across. 1024px covers the largest of those on
    /// a 3x display with room to spare.
    ///
    /// This matters because the source artwork is far larger than any of those:
    /// posters run to 2000x497 and 1181x1181, which decode to 4-6 MB each. Held
    /// at full size, a few dozen scrolled rows fill the cache's entire budget
    /// with bitmaps that are never drawn above 200px.
    /// `nonisolated` so `downsampledImage(from:)`, which runs off the main
    /// actor, can read it — it is an immutable `Int`, so there is nothing to
    /// serialise.
    nonisolated private static let maxPixelSize = 1024

    /// Decodes `data` at no more than `maxPixelSize` on its longest edge.
    ///
    /// Uses ImageIO's `kCGImageSourceCreateThumbnailFromImageAlways`, which
    /// scales *during* decode — the full-size bitmap is never allocated, so
    /// peak memory stays near the downsampled size rather than spiking to the
    /// original's. Falls back to a plain decode if ImageIO can't read the data.
    nonisolated private static func downsampledImage(from data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions)
        else { return UIImage(data: data) }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honour EXIF orientation, as `UIImage(data:)` would.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Only scales down: an image already smaller than the limit is
            // decoded at its own size rather than being blown up.
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return UIImage(data: data) }

        return UIImage(cgImage: thumbnail)
    }
}

/// Drop-in replacement for `AsyncImage` that serves repeat views from cache.
///
/// A cached image is returned synchronously on first render, so a row that has
/// been shown before never flashes its placeholder again.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    /// Bumped by `ImageStore.invalidateAll()`. `.task` keys on this as well as
    /// the URL, because a replaced picture keeps its address: without a second
    /// key the task would not re-run and the old bitmap would stay on screen.
    @State private var generation = ImageStore.generation

    /// The generation the currently-held `image` was loaded under, so the task
    /// can tell a refresh from a first appearance.
    ///
    /// `generation` alone can't: `.onReceive` writes the new value *before* the
    /// keyed task re-runs, so by the time it does, the two already agree and a
    /// refresh would be indistinguishable from an ordinary load.
    @State private var loadedGeneration = ImageStore.generation

    /// `.task(id:)` takes a single Equatable, so the two keys travel together.
    private struct Key: Equatable {
        let url: URL
        let generation: Int
    }

    init(
        url: URL,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        // Seed from cache during init so cached rows render on the first frame
        // rather than after a placeholder flash.
        _image = State(initialValue: ImageStore.shared.cached(url))
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onReceive(ImageStore.invalidationPublisher) { generation = $0 }
        .task(id: Key(url: url, generation: generation)) {
            // Re-ask the store rather than trusting this view's own earlier
            // attempt: its negative cache expires, so a listing that gained a
            // picture since we last looked resolves on the next appearance
            // (a pull-to-refresh rebuilds these rows) instead of staying blank
            // until the app restarts.
            //
            // On an invalidation the generation changes, so this re-runs even
            // though the URL did not: `image` is cleared first so the store is
            // actually consulted rather than the stale bitmap short-circuiting
            // the guard below.
            // A generation newer than the one this view last loaded under means
            // a refresh asked for the server's current copy, so that pass
            // revalidates; a first appearance or a plain re-appearance does not.
            let isRefresh = generation != loadedGeneration
            if isRefresh { image = nil }
            loadedGeneration = generation
            guard image == nil, !ImageStore.shared.isKnownMissing(url) else { return }
            image = await ImageStore.shared.image(for: url, revalidate: isRefresh)
        }
    }
}
