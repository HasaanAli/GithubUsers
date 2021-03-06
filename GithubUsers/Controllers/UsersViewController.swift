//
//  UsersViewController.swift
//  GithubUsers
//
//  Created by Hasaan Ali on 12/18/20.
//  Copyright © 2020 Hasaan Ali. All rights reserved.
//

import UIKit

class UsersViewController: UIViewController, AlertCreator {
    private let tag = "UsersViewController -"

    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var networkAvailabilityLabel: NetworkAvailabilityView!

    /// View controller's view model.
    private var viewModel: UsersViewModel!

    private var coredataManager: CoreDataManager = {
        let coredatamanager = CoreDataManager()
        AppDelegate.coreDataManager = coredatamanager
        return coredatamanager
    }()

    private var githubApiClient = GithubApiClient()

    /// Is table view showing filtered data.
    private var isFiltered = false
    private var reachedEndOfData = false

    override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.delegate = self
        searchBar.showsCancelButton = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard))
        tapGesture.cancelsTouchesInView = false;
        self.view.addGestureRecognizer(tapGesture)

        // Register non-storyboard cell classes
        tableView.register(LoadingTableViewCell.self, forCellReuseIdentifier: LoadingTableViewCell.CellIdentifier)

        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self

        viewModel = UsersViewModel(
            apiPageSize: 30,
            apiClient: githubApiClient,
            coreDataManager: coredataManager)
        viewModel.delegate = self

        networkAvailabilityLabel.isHidden = true
        //TODO: Register with Reachability instance
    }

    @objc func dismissKeyboard() {
        NSLog("%@ dismissKeyboard", tag)
        self.searchBar.resignFirstResponder()
    }
}

extension UsersViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let storyBoard = UIStoryboard(name: "Main", bundle:nil)
        let svcIdentifier = "UserDetailsViewController"
        guard let detailViewController = storyBoard.instantiateViewController(withIdentifier: svcIdentifier)
            as? UserDetailsViewController  else {
                NSLog("%@ Failed to open details screen. Failed to instantiate VC with identifier %@", tag, svcIdentifier)
                return
        }

        // Tapped cell's cellViewModel.
        let tappedCellViewModel = viewModel.cellViewModel(at: indexPath.row)
        let userDetailViewModel = UserDetailsViewModel(
            cellViewModel: tappedCellViewModel,
            indexPath: indexPath,
            apiClient: githubApiClient,
            coredataManager: coredataManager)
        
        userDetailViewModel.delegate = detailViewController
        detailViewController.viewModel = userDetailViewModel

        detailViewController.delegate = self
        self.navigationController?.pushViewController(detailViewController, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == viewModel.currentCount { // last row with indicator
            viewModel.loadData()
        }
    }
}

extension UsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.currentCount + (viewModel.isFilteringg ? 0 : 1) // +1 for activity indicator row when not filtering
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // LoadingTableViewCell doesn't conform to UsersTableViewCellProtocol, because it only has a UIActivityIndicator
        if indexPath.row == viewModel.currentCount && !viewModel.isFilteringg { // if its the activity indicator row
            let loadingCell =  tableView.dequeueReusableCell(withIdentifier: LoadingTableViewCell.CellIdentifier, for: indexPath) as! LoadingTableViewCell
            loadingCell.indicatorView?.startAnimating()
            return loadingCell
        } else {
            let cellViewModel = viewModel.cellViewModel(at: indexPath.row)
            return cellViewModel.cellForTableView(tableView: tableView, atIndexPath: indexPath)
        }
    }
}

extension UsersViewController: UsersViewModelDelegate {
    func onCellViewModelsChanged() {
        DispatchQueue.main.async {
            self.networkAvailabilityLabel.setFor(networkAvailable: true)
            // don't change isHidden
            self.tableView.reloadData()
        }
    }

    func onCellViewModelsUpdated(at indexPaths: [IndexPath]) {
        DispatchQueue.main.async {
            self.networkAvailabilityLabel.setFor(networkAvailable: true)
            self.tableView.reloadData()
            // tableView.cellForRow(at: ind)
            // TODO begin and end updates
            // tableView.reloadRows(at: indexPaths, with: .automatic)
        }
    }

    func onImageReady(at indexPath: IndexPath) {
        DispatchQueue.main.async {
            self.networkAvailabilityLabel.setFor(networkAvailable: true)
            if let visibleRows = self.tableView.indexPathsForVisibleRows, visibleRows.contains(indexPath) {
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        }
    }

    func onNoDataChanged() {
        NSLog("%@ onNoDataChanged", tag)
        NSLog("%@ Will set reachedEndOfData true.", tag)

        DispatchQueue.main.async {
            self.networkAvailabilityLabel.setFor(networkAvailable: true)
            self.reachedEndOfData = true
            // Reload tableview
            let totalRows = self.tableView.numberOfRows(inSection: 0)
            let lastRowIndexPath = IndexPath(row: totalRows - 1, section: 0)
            self.tableView.beginUpdates()
            self.tableView.deleteRows(at: [lastRowIndexPath], with: .middle)
            self.tableView.endUpdates()
        }
    }

    func onLoadFailed(with error: DataResponseError) {
        NSLog("%@ onLoadFailed(with error:) - \(error.description)", tag)
        DispatchQueue.main.async {
            switch error {
            case .network: // Inform user about network & retry
                self.networkAvailabilityLabel.setFor(networkAvailable: false)
                self.networkAvailabilityLabel.isHidden = false
            case .decoding:
                self.networkAvailabilityLabel.showWith(customBadText: "Data parsing error. Please email dev@g.com")
            }
        }
    }
}

extension UsersViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        NSLog("%@ Filter by '\(searchText)'", tag)
        viewModel.filterData(by: searchText)
    }
}

// UsersViewController also can directly make its ViewModel a delegate to UserDetailsViewController,
// but lets not do it for now
extension UsersViewController: UserDetailsViewControllerDelegate {
    func onCellViewModelChanged(to cellViewModel: UserCellViewModelProtocol, atVisibleIndexPath visibleIndexPath: IndexPath) {
        viewModel.update(cellViewModel: cellViewModel, at: visibleIndexPath)
    }
}
