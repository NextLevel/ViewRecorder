//  ViewRecorder.swift
//
//  Created by patrick piemonte on 6/13/19.
//
//  The MIT License (MIT)
//
//  Copyright (c) 2019-present patrick piemonte (http://patrickpiemonte.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import Foundation

public enum ViewRecorderError: Error, CustomStringConvertible {
    case cancelled
    case noOutputFile
    
    public var description: String {
        get {
            switch self {
            case .cancelled:
                return "Cancelled"
            case .noOutputFile:
                return "No Output File"
            }
        }
    }
}

public final class ViewRecorder {
    
    // MARK: - types
    
    public typealias ProgressHandler = (_ progress: Float) -> Void
    public typealias ResultHandler = (Swift.Result<URL, Error>) -> Void
    
    // MARK: - properties
    
    public var outputFileUrl: URL? {
        didSet {
            self._videoWriter.outputFileUrl = self.outputFileUrl
        }
    }
    
    public var framesPerSecond: Int32 = 60 {
        didSet {
            self._videoWriter.framesPerSecond = self.framesPerSecond
        }
    }
    
    // MARK: - ivars
    
    fileprivate var _videoWriter: VideoWriter = VideoWriter()
    fileprivate var _sourceView: UIView?
    fileprivate var _progressHandler: ProgressHandler?
    fileprivate var _completionHandler: ResultHandler?
    
    fileprivate var _source: DispatchSourceTimer?
    fileprivate var _queue: DispatchQueue = DispatchQueue(label: "com.patrickpiemonte.ViewRecorder",
                                                          qos: .userInitiated,
                                                          autoreleaseFrequency: .workItem,
                                                          target: DispatchQueue.global())

    // MARK: - object lifecycle
    
    public init() {
    }
    
    deinit {
        self._sourceView = nil
        self._progressHandler = nil
        self._completionHandler = nil
    }
    
}

// MARK: - actions

extension ViewRecorder {
    
    public func startRecording(view: UIView, progressHandler: ViewRecorder.ProgressHandler? = nil,  completionHandler: ViewRecorder.ResultHandler? = nil) {
        self._sourceView = view
        self._videoWriter.outputSize = view.bounds.size
        self._progressHandler = progressHandler
        self._completionHandler = completionHandler
               
        self._videoWriter.startDate = Date()
        self._source = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: self._queue)
        self._source?.setEventHandler(handler: { [weak self] in
            DispatchQueue.main.sync {
                let progress: Float = 0.0
                self?._progressHandler?(progress)

                guard let sourceView = self?._sourceView else {
                    return
                }
                guard let image = self?.image(fromView: sourceView) else {
                    return
                }
                self?._videoWriter.writeFrame(image: image)
            }
        })
        self._source?.setCancelHandler(handler: { [weak self] in
            DispatchQueue.main.sync {
                self?._videoWriter.finish {
                    DispatchQueue.main.async {
                        if let url = self?._videoWriter.outputFileUrl {
                            self?._completionHandler?(.success(url))
                        } else {
                            self?._completionHandler?(.failure(ViewRecorderError.cancelled))
                        }
                    }
                }
            }
        })
        
        let repeatingTime: Int = Int(1000 / (self.framesPerSecond))
        self._source?.schedule(deadline: .now(), repeating: DispatchTimeInterval.milliseconds(repeatingTime))
        self._source?.resume()
    }
    
    public func stop() {
        self._source?.cancel()
        self._source = nil
        self._videoWriter.endDate = Date()
    }

}

extension ViewRecorder {
    
    fileprivate func image(fromView view: UIView) -> UIImage? {
        autoreleasepool { () -> UIImage? in
            UIGraphicsBeginImageContextWithOptions(view.frame.size, true, 0)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            let rasterizedView = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return rasterizedView
        }
    }
    
}

