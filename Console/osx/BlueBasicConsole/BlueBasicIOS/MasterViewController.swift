//
//  MasterViewController.swift
//  BlueBasicIOS
//
//  Created by tim on 10/3/14.
//  Copyright (c) 2014 tim. All rights reserved.
//

import UIKit

class MasterViewController: UITableViewController {

  var names = [Device]()
  var lastIndexPath: IndexPath?

  override func awakeFromNib() {
    super.awakeFromNib()
    if UIDevice.current.userInterfaceIdiom == .pad {
        self.clearsSelectionOnViewWillAppear = false
        self.preferredContentSize = CGSize(width: 320.0, height: 600.0)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.refreshControl = UIRefreshControl()
    self.refreshControl?.addTarget(self, action: #selector(MasterViewController.pullToRefresh(_:)), for: .valueChanged)
    scan()
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  func scan() {
    deviceManager.findDevices() {
      device in
      if !self.names.contains(device) {
        self.names.append(device)
      }
      self.tableView.reloadData()
    }
  }
  
  func resignActive() {
    if let path = lastIndexPath {
      self.tableView.cellForRow(at: path)?.backgroundColor = nil
      lastIndexPath = nil
    }
  }
  
  @objc func pullToRefresh(_ sender: UIRefreshControl) {
    resignActive()
    names.removeAll(keepingCapacity: true)
    tableView.reloadData();
    sender.endRefreshing()
  }
  
  // MARK: - Segues

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "showDetail" {
      if let indexPath = self.tableView.indexPathForSelectedRow {
        if let path = lastIndexPath {
          self.tableView.cellForRow(at: path)?.backgroundColor = nil
          lastIndexPath = nil
        }
        self.tableView.cellForRow(at: indexPath)?.backgroundColor = UIColor.lightGray
        lastIndexPath = indexPath
        let device = names[indexPath.row]
        let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
        controller.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
        controller.navigationItem.leftItemsSupplementBackButton = true
        controller.detailItem = device
        popover?.dismiss(animated: true)
      }
    }
  }

  // MARK: - Table View

  override func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return names.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as UITableViewCell
    cell.textLabel?.text = names[indexPath.row].name
    switch names[indexPath.row].rssi {
    case -41...0:
      cell.imageView?.image = UIImage(named: "5bars")
    case -53...(-42):
      cell.imageView?.image = UIImage(named: "4bars")
    case -65...(-54):
      cell.imageView?.image = UIImage(named: "3bars")
    case -75...(-66):
      cell.imageView?.image = UIImage(named: "2bars")
    case -97...(-76):
      cell.imageView?.image = UIImage(named: "1bars")
    default:
      cell.imageView?.image = UIImage(named: "0bars")
    }
    cell.imageView?.sizeToFit()
    return cell
  }
}

