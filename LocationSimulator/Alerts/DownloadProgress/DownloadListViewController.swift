//
//  DownloadListViewController.swift
//  LocationSimulator
//
//  Created by David Klopp on 22.01.23.
//  Copyright © 2023 David Klopp. All rights reserved.
//

import Foundation
import Downloader
import AppKit

let kDevDiskTaskID = "DevDisk"
let kDevSignTaskID = "DevSign"

public enum DownloadStatus: Int {
    case failure
    case success
    case cancel
}

typealias DownloadCompletionHandler = (DownloadStatus) -> Void

class DownloadListViewController: NSViewController {
    /// The downloader instance to manage.
    public let downloader: Downloader = Downloader()

    /// The action to perform when the download is finished.
    public var downloadFinishedAction: DownloadCompletionHandler?

    /// True if the download progress is active.
    private var isDownloading = false

    /// True if the support directory is currently accessed, False otherwise
    public private(set) var isAccessingSupportDir: Bool = false

    private var progressListView: ProgressListView? {
        self.view as? ProgressListView
    }

    private var taskMap: [String: DownloadTaskWrapper] = [:]

    init() {
        super.init(nibName: nil, bundle: nil)
        self.downloader.delegate = self
    }

    override func loadView() {
        self.view = ProgressListView(frame: CGRect(x: 0, y: 0, width: 400, height: 140))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func prepareDownload(os: String, iOSVersion: String) -> Bool {
        // Check if the path for the image and signature file can be created.
        let manager = FileManager.default
        guard let devDMG = manager.getDeveloperDiskImage(os: os, version: iOSVersion),
              let devSign = manager.getDeveloperDiskImageSignature(os: os, version: iOSVersion) else {
            return false
        }

        // Get the download links from the internal plist file.
        let (diskLinks, signLinks) = manager.getDeveloperDiskImageDownloadLinks(os: os, version: iOSVersion)
        if diskLinks.isEmpty || signLinks.isEmpty {
            return false
        }

        // We use the first download link. In theory we could add multiple links for the same image.
        let devDiskTask = DownloadTask(dID: kDevDiskTaskID, source: diskLinks[0], destination: devDMG,
                                       description: "DEVDISK_DOWNLOAD_DESC".localized)
        let devSignTask = DownloadTask(dID: kDevSignTaskID, source: signLinks[0], destination: devSign,
                                       description: "DEVSIGN_DOWNLOAD_DESC".localized)
        let devDiskWrapper = DownloadTaskWrapper(downloadTask: devDiskTask)
        let devSignWrapper = DownloadTaskWrapper(downloadTask: devSignTask)

        self.taskMap = [devDiskTask.dID: devDiskWrapper, devSignTask.dID: devSignWrapper]

        self.progressListView?.add(task: devDiskWrapper)
        self.progressListView?.add(task: devSignWrapper)

        return true
    }

    /// Start the download of the DeveloperDiskImages.
    /// - Return: true on success, false otherwise.
    @discardableResult
    @objc func startDownload() -> Bool {
        guard !self.isDownloading else { return false }

        self.isDownloading = true
        // Start the downlaod process.
        self.isAccessingSupportDir = FileManager.default.startAccessingSupportDirectory()
        self.progressListView?.tasks.forEach {
            guard let task = ($0 as? DownloadTaskWrapper)?.task else { return }
            self.downloader.start(task)
        }
        return true
    }

    /// Cancel the current download.
    /// - Return: true on success, false otherwise.
    @discardableResult
    @objc func cancelDownload() -> Bool {
        guard self.isDownloading else { return false }

        self.progressListView?.tasks.forEach {
            guard let taskWrapper = ($0 as? DownloadTaskWrapper) else { return }
            self.downloader.cancel(taskWrapper.task)
        }

        // Cleanup
        self.isDownloading = false
        return true
    }
}

extension DownloadListViewController: DownloaderDelegate {
    func downloadStarted(downloader: Downloader, task: DownloadTask) {
        self.taskMap[task.dID]?.onProgress?(0)
    }

    func downloadProgressChanged(downloader: Downloader, task: DownloadTask) {
        self.taskMap[task.dID]?.onProgress?(Float(task.progress))
    }

    func downloadCanceled(downloader: Downloader, task: DownloadTask) {
        /*DispatchQueue.main.async {
            self.taskMap[task.dID]?.onError?(error) // TODO: Send some cancel error
        }*/

        guard downloader.tasks.count == 0 else { return }
        self.taskMap = [:]

        if self.isAccessingSupportDir { FileManager.default.stopAccessingSupportDirectory() }
        self.downloadFinishedAction?(.cancel)
    }

    func downloadFinished(downloader: Downloader, task: DownloadTask) {
        self.taskMap[task.dID]?.onCompletion?(Float(task.progress))
        self.taskMap.removeValue(forKey: task.dID)

        guard downloader.tasks.count == 0 else { return }
        if self.isAccessingSupportDir { FileManager.default.stopAccessingSupportDirectory() }
        // Give the animations some time to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.downloadFinishedAction?(.success)
        }
    }

    func downloadError(downloader: Downloader, task: DownloadTask, error: Error) {
        if self.isAccessingSupportDir { FileManager.default.stopAccessingSupportDirectory() }
        self.taskMap[task.dID]?.onError?(error)
        self.downloadFinishedAction?(.failure)
    }
}
