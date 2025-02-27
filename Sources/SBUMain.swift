//
//  SBUMain.swift
//  SendBirdUIKit
//
//  Created by Tez Park on 27/02/2020.
//  Copyright © 2020 Sendbird, Inc. All rights reserved.
//

import UIKit
import SendBirdSDK

@objcMembers
public class SBUMain: NSObject {
    // MARK: - Initialize
    /// This function is used to initializes SDK with applicationId.
    /// - Parameter applicationId: Application ID
    @available(*, unavailable, message: "Using the `initialize(applicationId:migrationStartHandler:completionHandler:)` function, and in the CompletionHandler, please proceed with the following procedure.", renamed: "initialize(applicationId:migrationStartHandler:completionHandler:)") // 2.2.0
    public static func initialize(applicationId: String) {
        SBUMain.initialize(applicationId: applicationId) {
            
        } completionHandler: { error in
            
        }
    }
    
    /// This function is used to initializes SDK with applicationId.
    ///
    /// When the completion handler is called, please proceed with the next operation.
    ///
    /// - Parameters:
    ///   - applicationId: Application ID
    ///   - migrationStartHandler: Do something to display the progress of the DB migration.
    ///   - completionHandler: Do something to display the completion of the DB migration.
    ///
    /// - Since: 2.2.0
    public static func initialize(applicationId: String,
                                  migrationStartHandler: @escaping (() -> Void),
                                  completionHandler: @escaping ((_ error: SBDError?) -> ())) {
        SBUGlobals.ApplicationId = applicationId
        
        SBDMain.addExtension(SBUConstant.sbdExtensionKeyUIKit, version: SBUMain.shortVersion)
    
        SBDMain.initWithApplicationId(
            applicationId,
            useCaching: true,
            migrationStartHandler: {
                SBULog.info("[Init] Migration start")
                migrationStartHandler()
            }, completionHandler: { error in
                if let _ = error {
                    SBULog.info("[Init] Failed initialized with id: \(applicationId)")
                } else {
                    SBULog.info("[Init] Finish initialized with id: \(applicationId)")
                }
                
                completionHandler(error)
            })
    }
    
    
    // MARK: - Connection
    /// This function is used to connect to the Sendbird server or local cahing database.
    ///
    /// Before invoking this function, `CurrentUser` object of `SBUGlobals` claas must be set.
    /// - Parameter completionHandler: The handler block to execute.
    public static func connect(
        completionHandler: @escaping (_ user: SBDUser?, _ error: SBDError?) -> Void
    ) {
        SBUMain.connectIfNeeded(completionHandler: completionHandler)
    }
    
    @available(*, deprecated, renamed: "connectIfNeeded(completionHandler:)") // 2.2.0
    public static func connectionCheck(
        completionHandler: @escaping (_ user: SBDUser?, _ error: SBDError?) -> Void
    ) {
        self.connectIfNeeded(completionHandler: completionHandler)
    }
    
    
    /// This function is used to check the connection state.
    ///  if connected, returns the SBDUser object, otherwise, call the connect function from the inside.
    ///  If local caching is enabled, the currentUser object is delivered and the connect operation is performed.
    ///
    /// - Parameter completionHandler: The handler block to execute.
    public static func connectIfNeeded(
        completionHandler: @escaping (_ user: SBDUser?, _ error: SBDError?) -> Void
    ) {
        SBULog.info("[Check] Connection status : \(SBDMain.getConnectState().rawValue)")
        
        if SBDMain.getConnectState() == .open {
            completionHandler(SBDMain.getCurrentUser(), nil)
        } else {
            SBULog.info("currentUser: \(String(describing: SBDMain.getCurrentUser()?.userId))")
            if SBDMain.isUsingLocalCaching(),
               let _ = SBDMain.getCurrentUser() {
                completionHandler(SBDMain.getCurrentUser(), nil)
                SBUMain.connectAndUpdates { _, _ in }
            } else {
                SBUMain.connectAndUpdates(completionHandler: completionHandler)
            }
        }
    }
    
    /// This function is used to check connection state and connect to the Sendbird server or local caching database.
    /// - Parameter completionHandler: The handler block to execute.
    static func connectAndUpdates(
        completionHandler: @escaping (_ user: SBDUser?, _ error: SBDError?) -> Void
    ) {
        SBULog.info("[Request] Connection to Sendbird")
        
        guard let currentUser = SBUGlobals.CurrentUser else {
            SBULog.error("[Failed] Connection to Sendbird: CurrentUser value is not set")
            completionHandler(SBDMain.getCurrentUser(), nil)
            return
        }
        
        let userId = currentUser.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = currentUser.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        SBDMain.connect(withUserId: userId, accessToken: SBUGlobals.AccessToken) { [userId, nickname] user, error in
            defer {
                SBUEmojiManager.loadAllEmojis { _, error in }
            }
            
            guard let user = user else {
                SBULog.error("[Failed] Connection to Sendbird: \(error?.localizedDescription ?? "")")
                completionHandler(nil, error)
                return
            }
            
            if let error = error {
                SBULog.warning("[Warning] Connection to Sendbird: Succeed but error was occurred: \(error.localizedDescription)")
                completionHandler(user, error)
                return
            }
            
            SBULog.info("[Succeed] Connection to Sendbird")
            
            var updatedNickname = nickname
            
            if updatedNickname == nil {
                if let currentNickname = user.nickname, !currentNickname.isEmpty {
                    updatedNickname = user.nickname
                } else {
                    updatedNickname = userId
                }
            }
            
            SBUMain.updateUserInfo(
                nickname: updatedNickname,
                profileUrl: currentUser.profileUrl ?? user.profileUrl
            ) { error in
                
                #if !targetEnvironment(simulator)
                if let pendingPushToken = SBDMain.getPendingPushToken() {
                    SBULog.info("[Request] Register pending push token to Sendbird server")
                    SBUMain.registerPush(deviceToken: pendingPushToken) { success in
                        if !success {
                            SBULog.error("[Failed] Register pending push token to Sendbird server")
                        }
                        SBULog.info("[Succeed] Register pending push token to Sendbird server")
                    }
                }
                #endif
                
                completionHandler(user, error)
            }
        }
    }
    
    public static func updateUserInfo(completionHandler: @escaping (_ error: SBDError?) ->Void) {
        guard let sbuUser = SBUGlobals.CurrentUser else {
            SBULog.error("[Failed] Connection to Sendbird: CurrentUser value is not set")
            completionHandler(nil)
            return
        }
        guard let sbdUser = SBDMain.getCurrentUser() else {
            SBULog.error("[Failed] Connection to Sendbird")
            completionHandler(nil)
            return
        }
        
        let userId = sbuUser.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = sbuUser.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var updatedNickname = nickname
        
        if updatedNickname == nil {
            if let currentNickname = sbdUser.nickname, !currentNickname.isEmpty {
                updatedNickname = sbdUser.nickname
            } else {
                updatedNickname = userId
            }
        }
        
        SBUMain.updateUserInfo(
            nickname: updatedNickname,
            profileUrl: sbuUser.profileUrl ?? sbdUser.profileUrl
        ) { error in
            
            #if !targetEnvironment(simulator)
            if let pendingPushToken = SBDMain.getPendingPushToken() {
                SBULog.info("[Request] Register pending push token to Sendbird server")
                SBUMain.registerPush(deviceToken: pendingPushToken) { success in
                    if !success {
                        SBULog.error("[Failed] Register pending push token to Sendbird server")
                    }
                    SBULog.info("[Succeed] Register pending push token to Sendbird server")
                }
            }
            #endif
            
            completionHandler(error)
        }
    }
    
    /// This function is used to disconnect
    /// - Parameter completionHandler: The handler block to execute.
    public static func disconnect(completionHandler: (() -> Void)?) {
        SBULog.info("[Request] Disconnection to Sendbird")
        
        SBDMain.disconnect(completionHandler: {
            SBULog.info("[Succeed] Disconnection to Sendbird")
            SBUGlobals.CurrentUser = nil
            completionHandler?()
        })
    }
    
    
    // MARK: - UserInfo
    /// This function is used to update user information.
    /// - Parameters:
    ///   - nickname: Nickname to use for update. If this value is nil, the nickname is not updated.
    ///   - profileUrl: Profile URL to use for update. If this value is nil, the profile is not updated.
    ///   - completionHandler: The handler block to execute.
    public static func updateUserInfo(nickname: String?,
                                      profileUrl: String?,
                                      completionHandler: ((_ error: SBDError?) -> Void)?) {
        SBULog.info("[Request] Update user info")
        SBDMain.updateCurrentUserInfo(
            withNickname: nickname,
            profileUrl: profileUrl
        ) { error in
            self.didFinishUpdateUserInfo(error: error, completionHandler: completionHandler)
        }
    }
    
    /// This function is used to update user information.
    /// - Parameters:
    ///   - nickname: Nickname to use for update. If this value is nil, the nickname is not updated.
    ///   - profileImage: Profile image to use for update. If this value is nil, the profile is not updated.
    ///   - completionHandler: The handler block to execute.
    public static func updateUserInfo(nickname: String?,
                                      profileImage: Data?,
                                      completionHandler: ((_ error: SBDError?) -> Void)?) {
        SBULog.info("[Request] Update user info")
        SBDMain.updateCurrentUserInfo(
            withNickname: nickname,
            profileImage: profileImage,
            progressHandler: nil
        ) { error in
            self.didFinishUpdateUserInfo(error: error, completionHandler: completionHandler)
        }
    }
    
    private static func didFinishUpdateUserInfo(error: SBDError?,
                                                completionHandler: ((_ error: SBDError?) -> Void)?) {
        if let error = error {
            SBULog.error("[Failed] Update user info: \(error.localizedDescription)")
            completionHandler?(error)
            return
        }
        
        SBULog.info("""
            [Succeed]
            Update user info: \(String(SBUGlobals.CurrentUser?.description ?? ""))
            """)
        
        if let user = SBDMain.getCurrentUser() {
            SBUGlobals.CurrentUser = SBUUser(
                userId: user.userId,
                nickname: user.nickname ?? user.userId,
                profileUrl: user.profileUrl
            )
        }
        
        completionHandler?(nil)
    }
    
    
    // MARK: - Common
    /// This function gets UIKit SDK's short version string. (e.g. 1.0.0)
    /// - Since: 2.2.0
    public static let shortVersion: String = "2.2.3"
    
    /// This function gets UIKit SDK's version string.
    /// - Returns: version string
    public static func versionString() -> String? {
        let bundle = Bundle(identifier: "com.sendbird.uikit")
        if let build = bundle?.infoDictionary?[kCFBundleVersionKey as String] {
            return "\(build)"
        }
        
        return nil
    }
    
    @available(*, unavailable, renamed: "shortVersion") // 2.2.0
    public static func getUIKitVersion() -> String {
        SBUMain.shortVersion
    }
    
    /// This function gets UIKit SDK's short version string.
    /// - Returns: short version string
    @available(*, unavailable, renamed: "shortVersion") // 2.2.0
    public static func shortVersionString() -> String? {
        let bundle = Bundle(identifier: "com.sendbird.uikit")
        if let shortVersion = bundle?.infoDictionary?["CFBundleShortVersionString"] {
            return "\(shortVersion)"
        }

        return nil
    }

    
    // MARK: - Push Notification
    
    /// This function is used to register push token for using push service on the Sendbird server.
    /// - Parameters:
    ///   - deviceToken: Device token
    ///   - completionHandler: The handler block to execute.
    public static func registerPush(deviceToken: Data,
                                    completionHandler: @escaping (_ success: Bool) -> Void) {
        SBULog.info("[Request] Register push token to Sendbird server")
        
        #if !targetEnvironment(simulator)
        SBDMain.registerDevicePushToken(deviceToken, unique: true) { status, error in
            switch status {
            case .success:
                SBULog.info("[Succeed] APNs push token is registered.")
                completionHandler(true)
            case .pending:
                SBULog.info("[Response] Push registration is pending.")
                completionHandler(false)
            case .error:
                SBULog.error("""
                    [Failed]
                    APNs registration failed with error: \(String(describing: error ?? nil))
                    """)
                completionHandler(false)
            @unknown default:
                SBULog.error("[Failed] Push registration: unknown default")
                completionHandler(false)
            }
        }
        #else
        completionHandler(false)
        #endif
    }
    
    /// This function is used to unregister push token on the Sendbird server.
    /// - Parameter completionHandler: The handler block to execute.
    public static func unregisterPushToken(completionHandler: @escaping (_ success: Bool) -> Void) {
        SBUMain.connectIfNeeded { user, error in
        guard error == nil else { return }
            
            #if !targetEnvironment(simulator)
            guard let pendingPushToken = SBDMain.getPendingPushToken() else { return }
            SBULog.info("[Request] Unregister push token to Sendbird server")
            SBDMain.unregisterPushToken(pendingPushToken) { resonse, error in
                if let error = error {
                    SBULog.error("""
                        [Failed]
                        Push unregistration is fail: \(error.localizedDescription)
                        """)
                    completionHandler(false)
                    return
                }
                
                SBULog.info("[Succeed] Push unregistration is success.")
                completionHandler(true)
            }
            #else
            completionHandler(false)
            #endif
        }
    }
    
    /// This function is used to unregister all push token on the Sendbird server.
    /// - Parameter completionHandler: The handler block to execute.
    public static func unregisterAllPushToken(completionHandler: @escaping (_ success: Bool) -> Void) {
        SBUMain.connectIfNeeded { user, error in
        guard error == nil else { return }
            
            SBULog.info("[Request] Unregister all push token to Sendbird server")
            
            SBDMain.unregisterAllPushToken { resonse, error in
                if let error = error {
                    SBULog.error("[Failed] Push unregistration is fail: \(error.localizedDescription)")
                    completionHandler(false)
                    return
                }
                
                SBULog.info("[Succeed] Push unregistration is success.")
                completionHandler(true)
            }
        }
    }
    
    @available(*, deprecated, renamed: "moveToChannel(channelUrl:basedOnChannelList:messageListParams:)") // 1.2.2
    public static func openChannel(channelUrl: String,
                                   basedOnChannelList: Bool = true,
                                   messageListParams: SBDMessageListParams? = nil) {
        moveToChannel(
            channelUrl: channelUrl,
            basedOnChannelList: basedOnChannelList,
            messageListParams: messageListParams
        )
    }
    
    /// This is a function that moves the channel that can be called anywhere.
    ///
    /// If you wish to open an open channel view controller, or any class that subclasses `SBUOpenChannelViewController`,
    /// you must guarentee that a channel list's view controller, subclass of `SBUBaseChannelListViewController`,
    /// is present within the `UINavigationController.viewControllers` if you set the `basedOnChannelList` to `true`.
    ///
    /// - Parameters:
    ///   - channelUrl: channel url for use in channel.
    ///   - basedOnChannelList: `true` for services based on the channel list. Default value is `true`
    ///   - messageListParams: If there is a messageListParams set directly for use in Channel, set it up here
    /// - Since: 1.2.2
    public static func moveToChannel(channelUrl: String,
                                     basedOnChannelList: Bool = true,
                                     messageListParams: SBDMessageListParams? = nil,
                                     channelType: ChannelType = .group) {
        guard SBUGlobals.CurrentUser != nil else { return }
        
        var rootViewController = UIApplication.shared.keyWindow?.rootViewController
        
        if let tabbarController: UITabBarController = rootViewController?.presentedViewController as? UITabBarController {
            rootViewController = tabbarController.selectedViewController
        }
        else if let tabbarController: UITabBarController = rootViewController as? UITabBarController {
            rootViewController = tabbarController.selectedViewController
        }
        
        // If search view controller is found, dismiss it first (it'll be in different navigation controller)
        if let searchViewController = findSearchViewController(rootViewController: rootViewController) {
            // Dismiss any presented view controllers before pushing other vc on top
            searchViewController.presentedViewController?.dismiss(animated: false, completion: nil)
            
            searchViewController.dismiss(animated: false) {
                let viewController: UIViewController? = findChannelViewController(
                    rootViewController: rootViewController,
                    channelType: channelType
                )
                showChannelViewController(with: viewController ?? rootViewController,
                                          channelUrl: channelUrl,
                                          basedOnChannelList: basedOnChannelList,
                                          messageListParams: messageListParams,
                                          channelType: channelType)
            }
        } else {
            let viewController: UIViewController? = findChannelViewController(
                rootViewController: rootViewController,
                channelType: channelType
            )
            showChannelViewController(with: viewController ?? rootViewController,
                                      channelUrl: channelUrl,
                                      basedOnChannelList: basedOnChannelList,
                                      messageListParams: messageListParams,
                                      channelType: channelType)
        }
    }
    
    /// Shows channel viewcontroller.
    private static func showChannelViewController(with viewController: UIViewController?,
                                                  channelUrl: String,
                                                  basedOnChannelList: Bool,
                                                  messageListParams: SBDMessageListParams?,
                                                  channelType: ChannelType) {
        // Dismiss any presented view controllers before pushing other vc on top
        viewController?.presentedViewController?.dismiss(animated: false, completion: nil)
        
        if let channelListViewController = viewController as? SBUBaseChannelListViewController {
            channelListViewController
                .navigationController?
                .popToViewController(channelListViewController, animated: false)
            
            channelListViewController.showChannel(channelUrl: channelUrl)
        } else if let channelViewController = viewController as? SBUBaseChannelViewController {
            channelViewController.loadChannel(channelUrl: channelUrl,
                                              messageListParams: messageListParams)
        } else {
            let isGroupChannel = channelType == .group
            if basedOnChannelList {
                // If based on channelList.
                // FIXME: - Needs a way to get user's open channel list vc?? (not in SDK)
                let vc: SBUBaseChannelListViewController = isGroupChannel ? SBUChannelListViewController() : SBUBaseChannelListViewController()
                let naviVC = UINavigationController(rootViewController: vc)
                viewController?.present(naviVC, animated: true, completion: {
                    vc.showChannel(channelUrl: channelUrl)
                })
            } else {
                // If based on channel
                let vc: SBUBaseChannelViewController
                if isGroupChannel {
                    vc = SBUChannelViewController(
                        channelUrl: channelUrl,
                        messageListParams: messageListParams
                    )
                } else {
                    vc = SBUOpenChannelViewController(
                        channelUrl: channelUrl,
                        messageListParams: messageListParams
                    )
                }
                let naviVC = UINavigationController(rootViewController: vc)
                viewController?.present(naviVC, animated: true)
            }
        }
    }
    
    /// Finds instance of channel list or channel viewcontroller from the navigation controller's viewcontrollers.
    ///
    /// - Returns: instance of `SBUBaseChannelListViewController` or `SBUBaseChannelViewController`, or
    ///            `nil` if none are fonud.
    private static func findChannelViewController(rootViewController: UIViewController?,
                                                  channelType: ChannelType) -> UIViewController? {
        guard let navigationController: UINavigationController =
                rootViewController?.presentedViewController as? UINavigationController ??
                rootViewController as? UINavigationController else { return nil }
        
        if let channelListVc = navigationController
            .viewControllers
            .first(where: {
                if channelType == .group {
                    return $0 is SBUChannelListViewController
                } else {
                    // shouldn't be instance of SBUChannelListViewController since this is for group channel.
                    return !($0 is SBUChannelListViewController) && $0 is SBUBaseChannelListViewController
                }
            }) {
            return channelListVc
        } else {
            return navigationController
                .viewControllers
                .last(where: {
                    if channelType == .group {
                        return $0 is SBUChannelViewController
                    } else {
                        return $0 is SBUOpenChannelViewController
                    }
                })
        }
    }
    
    
    /// Finds instance of message shearch viewcontroller from the navigation controller's viewcontrollers.
    ///
    /// - Returns: instance of `SBUMessageSearchViewController`or `nil` if none are fonud.
    private static func findSearchViewController(rootViewController: UIViewController?) -> UIViewController? {
        guard let navigationController: UINavigationController =
                rootViewController?.presentedViewController as? UINavigationController ??
                rootViewController as? UINavigationController else { return nil }
        
        return navigationController
            .viewControllers
            .compactMap { $0 as? SBUMessageSearchViewController }
            .first
    }
    
    /// This is a function that creates and moves the channel that can be called anywhere.
    /// - Parameters:
    ///   - userIds: List of user ids
    ///   - messageListParams: If there is a messageListParams set directly for use in Channel, set it up here
    /// - Since: 1.2.2
    public static func createAndMoveToChannel(userIds: [String],
                                              messageListParams: SBDMessageListParams? = nil) {
        SBULog.info("""
            [Request] Create channel with users,
            User: \(userIds))
            """)
        
        let params = SBDGroupChannelParams()
        params.name = ""
        params.coverUrl = ""
        params.addUserIds(userIds)
        params.isDistinct = false
        
        if let currentUser = SBUGlobals.CurrentUser {
            params.operatorUserIds = [currentUser.userId]
        }
        
        SBUGlobalCustomParams.groupChannelParamsCreateBuilder?(params)
        
        self.createAndMoveToChannel(params: params, messageListParams: messageListParams)
    }
    
    /// This is a function that creates and moves the channel that can be called anywhere.
    /// - Parameters:
    ///   - params: `SBDGroupChannelParams` class object
    ///   - messageListParams: If there is a messageListParams set directly for use in Channel, set it up here
    /// - Since: 1.2.2
    public static func createAndMoveToChannel(params: SBDGroupChannelParams,
                                              messageListParams: SBDMessageListParams? = nil) {
        SBDGroupChannel.createChannel(with: params) { channel, error in
            if let error = error {
                SBULog.error("""
                    [Failed] Create channel request:
                    \(String(error.localizedDescription))
                    """)
            }
            
            guard let channelUrl = channel?.channelUrl else {
                SBULog.error("[Failed] Create channel request: There is no channel url.")
                return
            }
            SBULog.info("[Succeed] Create channel: \(channel?.description ?? "")")
            
            SBUMain.moveToChannel(channelUrl: channelUrl, messageListParams: messageListParams)
        }
    }

    
    // MARK: - Logger
    
    /// You can activate log information for debugging.
    ///
    /// - `Objective-C` uses bit masking. (e,g, `.error|.info`)
    /// - `Swift` uses a single type in this function.
    /// - default type: .none
    /// - Parameter type: LogType
    public static func setLogLevel(_ type: LogType) {
        SBULog.logType = type.rawValue
    }
    
    ///  You can activate log information for debugging. (*Swift only*)
    ///
    /// - This function  can uses multiple types.
    /// - default type: .none
    /// - Parameter types: [LogType]
    public static func setLogLevel(_ types: [LogType]) {
        let type = types.map {$0.rawValue}.reduce(0) {$0 + $1}
        SBULog.logType = type
    }
}

