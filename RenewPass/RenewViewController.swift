//
//  RenewViewController.swift
//  RenewPass
//
//  Created by Kino Roy on 2017-01-31.
//  Copyright © 2017 Kino Roy. All rights reserved.
//

import UIKit
import CoreData
import WebKit

class RenewViewController: UIViewController {
    
    // MARK: - Proporties
    var accounts:[NSManagedObject]!
    var webview:CustomWebView!
    var username:String!
    var school:Schools!
    var completionHandlers:[(Bool) -> Void] = []
    @IBOutlet weak var reloadButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!

    // MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = "Waiting on button click...."
        
        NotificationCenter.default.addObserver(forName: Notification.Name("webViewDidFinishLoading"), object: nil, queue: nil, using: webViewDidFinishLoad)
        
        self.reloadButton.isEnabled = true
        
        // Checks if there is login data stored. If not, asks the user for login data by showing the login screen.
        if needToShowLoginScreen() {
            showLoginScreen()
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if needToShowLoginScreen() {
            showLoginScreen()
        }
    }

    // MARK: - Navigation

    /// Displays the login screen
    func showLoginScreen() {
        
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let signInViewController = storyboard.instantiateViewController(withIdentifier: "signInViewController")
            
            self.present(signInViewController, animated: true) {
                
            }
        }
        
    }
    
    /// Determines if the login screen needs to be shown
    ///     Returns: A boolean describing whether to show the login screen or not
    func needToShowLoginScreen() -> Bool {
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Account")
        
        do {
            let results =
                try managedContext.fetch(fetchRequest)
            accounts = results as! [NSManagedObject]
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        
        return accounts.isEmpty
        
    }
    
    // MARK: - Actions
    
    @IBAction func renewButtonTouchUpInside(_ sender: Any) {
        reloadButton.isEnabled = false
        
        if UserDefaults.standard.bool(forKey: "showWebview") {
            self.view.addSubview(webview)
        }
        
        statusLabel.text = "Waiting for translink.ca"
        
        fetch() { (success) in
            if success {
                print("success")
            } else {
                print("didn't get the latest upass, maybe you have the latest?")
            }
        }
        
        
    }
    
    func selectSchool(school:Int16) {
        
        statusLabel.text = "Selecting school"
        webview.stringByEvaluatingJavaScript(from: getJavaScript(filename: "SelectSchool"))

    }
    
    func authenticate(school:Int16) throws {
        
        statusLabel.text = "Authenticating"
        
        switch school {
        case 9: // SFU
            let result = webview.stringByEvaluatingJavaScript(from: getJavaScript(filename: "AuthenticationError_SFU"))
            if result == "failure" {
                throw RenewPassException.authenticationFailedException
            }
            webview.stringByEvaluatingJavaScript(from: getJavaScript(filename: "Authenticate_SFU"))
        default:
            throw RenewPassException.schoolNotFoundException
        }
        
    }
    
    func checkUpass() throws {
        
        statusLabel.text = "Checking UPass"
        
        guard !(webview.request?.url?.absoluteString.contains("cas"))! else {
            throw RenewPassException.authenticationFailedException
        }
        
        let result = webview.stringByEvaluatingJavaScript(from: getJavaScript(filename: "CheckUPass"))
       
        guard result != "null" else {
            throw RenewPassException.alreadyHasLatestUPassException
        }
    }


    func getJavaScript(filename: String) -> String {
        let path = Bundle.main.path(forResource: filename, ofType: "js")
        let url = URL(fileURLWithPath: path!)
        do {
            var js = try String(contentsOf: url, encoding: String.Encoding.utf8)
            js = js.replacingOccurrences(of: "\n", with: "")
            js = js.replacingOccurrences(of: "storedUsername", with: username)
            js = js.replacingOccurrences(of: "storedPassword", with: KeychainSwift().get("accountPassword")! as String)
            js = js.replacingOccurrences(of: "_SCHOOL_ID_", with: "\(getSchoolID(school: school))")
            return js
        } catch {
            fatalError("Could not read the JavaScript file \"\(filename).js\"")
        }
    }
    
    // MARK: - Webview
    func webViewDidFinishLoad(notification:Notification) {
        //let webView = notification.object as! UIWebView
        guard let currentURL = webview.request?.url?.absoluteString else {
            fatalError("Webview did not load a URL")
        }
        
        do {
            if currentURL == "https://upassbc.translink.ca/" {
                //reloadButton.isEnabled = true
                //statusLabel.text = "Waiting on button click"
                selectSchool(school: getSchoolID(school: school))
            } else if currentURL.contains("cas") { // SFU authentication screen
                try authenticate(school: getSchoolID(school: school))
            } else if currentURL.contains("fs") { // post-auth Upass site
                try checkUpass()
            }
        } catch RenewPassException.authenticationFailedException {
            statusLabel.text = "Authentication failed"
            completionHandlers[0](false)
        } catch RenewPassException.alreadyHasLatestUPassException {
            statusLabel.text = "You already have the latest UPass"
            completionHandlers[0](false)
        } catch RenewPassException.schoolNotFoundException {
            statusLabel.text = "School Not Found / Not Supported"
            completionHandlers[0](false)
        } catch RenewPassException.unknownException {
            statusLabel.text = "Unknown Error"
            completionHandlers[0](false)
        } catch {
            statusLabel.text = "Unknown Error"
            completionHandlers[0](false)
        }
        
    }
    
    func fetch(completion: @escaping (_ success:Bool) -> Void) {
        completionHandlers.append(completion)
        
        if webview == nil {
            webview = CustomWebView(frame: self.view.frame)
            
            let url = URL(string: "https://upassbc.translink.ca")
            let urlRequest = URLRequest(url: url!)
            webview.loadRequest(urlRequest)
        
        }
        
        school = Schools.SFU
        
        //Get auth values
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Account")
        
        do {
            let results =
                try managedContext.fetch(fetchRequest)
            accounts = results as! [NSManagedObject]
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        
        username = accounts[0].value(forKey: "username") as! String!
        
        //selectSchool(school: getSchoolID(school: school))
        
        
    }
}

class CustomWebView: UIWebView
{
    var uiView = UIView()
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        self.delegate = self
    }
    
    convenience init(frame:CGRect, request:URLRequest)
    {
        self.init(frame: frame)
        uiView.addSubview(self)
        loadRequest(request)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CustomWebView: UIWebViewDelegate
{
    func webViewDidStartLoad(_ webView: UIWebView)
    {
        //print("webViewDidStartLoad")
    }
    
    func webViewDidFinishLoad(_ webView: UIWebView)
    {
        //print("webViewDidFinishLoad")
        NotificationCenter.default.post(name: Notification.Name("webViewDidFinishLoading"), object: nil)
    }
    
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error)
    {
        //print("An error occurred while loading the webview")
        print(error)
    }
}

// MARK: - Enum

enum RenewPassException: Error {
    case authenticationFailedException
    case schoolNotFoundException
    case alreadyHasLatestUPassException
    case unknownException
}
