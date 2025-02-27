require "test_helper"

module Api
  class WaysControllerTest < ActionDispatch::IntegrationTest
    ##
    # test all routes which lead to this controller
    def test_routes
      assert_routing(
        { :path => "/api/0.6/way/create", :method => :put },
        { :controller => "api/ways", :action => "create" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1/full", :method => :get },
        { :controller => "api/ways", :action => "full", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1/full.json", :method => :get },
        { :controller => "api/ways", :action => "full", :id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1", :method => :get },
        { :controller => "api/ways", :action => "show", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1.json", :method => :get },
        { :controller => "api/ways", :action => "show", :id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1", :method => :put },
        { :controller => "api/ways", :action => "update", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/way/1", :method => :delete },
        { :controller => "api/ways", :action => "delete", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/ways", :method => :get },
        { :controller => "api/ways", :action => "index" }
      )
      assert_routing(
        { :path => "/api/0.6/ways.json", :method => :get },
        { :controller => "api/ways", :action => "index", :format => "json" }
      )
    end

    # -------------------------------------
    # Test showing ways.
    # -------------------------------------

    def test_show
      # check that a visible way is returned properly
      get api_way_path(create(:way))
      assert_response :success

      # check that an invisible way is not returned
      get api_way_path(create(:way, :deleted))
      assert_response :gone

      # check chat a non-existent way is not returned
      get api_way_path(:id => 0)
      assert_response :not_found
    end

    ##
    # check the "full" mode
    def test_full
      way = create(:way_with_nodes, :nodes_count => 3)

      get way_full_path(way)

      assert_response :success

      # Check the way is correctly returned
      assert_select "osm way[id='#{way.id}'][version='1'][visible='true']", 1

      # check that each node in the way appears once in the output as a
      # reference and as the node element.
      way.nodes.each do |n|
        assert_select "osm way nd[ref='#{n.id}']", 1
        assert_select "osm node[id='#{n.id}'][version='1'][lat='#{format('%<lat>.7f', :lat => n.lat)}'][lon='#{format('%<lon>.7f', :lon => n.lon)}']", 1
      end
    end

    def test_full_deleted
      way = create(:way, :deleted)

      get way_full_path(way)

      assert_response :gone
    end

    ##
    # test fetching multiple ways
    def test_index
      way1 = create(:way)
      way2 = create(:way, :deleted)
      way3 = create(:way)
      way4 = create(:way)

      # check error when no parameter provided
      get ways_path
      assert_response :bad_request

      # check error when no parameter value provided
      get ways_path, :params => { :ways => "" }
      assert_response :bad_request

      # test a working call
      get ways_path, :params => { :ways => "#{way1.id},#{way2.id},#{way3.id},#{way4.id}" }
      assert_response :success
      assert_select "osm" do
        assert_select "way", :count => 4
        assert_select "way[id='#{way1.id}'][visible='true']", :count => 1
        assert_select "way[id='#{way2.id}'][visible='false']", :count => 1
        assert_select "way[id='#{way3.id}'][visible='true']", :count => 1
        assert_select "way[id='#{way4.id}'][visible='true']", :count => 1
      end

      # test a working call with json format
      get ways_path, :params => { :ways => "#{way1.id},#{way2.id},#{way3.id},#{way4.id}", :format => "json" }

      js = ActiveSupport::JSON.decode(@response.body)
      assert_not_nil js
      assert_equal 4, js["elements"].count
      assert_equal 4, (js["elements"].count { |a| a["type"] == "way" })
      assert_equal 1, (js["elements"].count { |a| a["id"] == way1.id && a["visible"].nil? })
      assert_equal 1, (js["elements"].count { |a| a["id"] == way2.id && a["visible"] == false })
      assert_equal 1, (js["elements"].count { |a| a["id"] == way3.id && a["visible"].nil? })
      assert_equal 1, (js["elements"].count { |a| a["id"] == way4.id && a["visible"].nil? })

      # check error when a non-existent way is included
      get ways_path, :params => { :ways => "#{way1.id},#{way2.id},#{way3.id},#{way4.id},0" }
      assert_response :not_found
    end

    # -------------------------------------
    # Test simple way creation.
    # -------------------------------------

    def test_create
      node1 = create(:node)
      node2 = create(:node)
      private_user = create(:user, :data_public => false)
      private_changeset = create(:changeset, :user => private_user)
      user = create(:user)
      changeset = create(:changeset, :user => user)

      ## First check that it fails when creating a way using a non-public user
      auth_header = basic_authorization_header private_user.email, "test"

      # use the first user's open changeset
      changeset_id = private_changeset.id

      # create a way with pre-existing nodes
      xml = "<osm><way changeset='#{changeset_id}'>" \
            "<nd ref='#{node1.id}'/><nd ref='#{node2.id}'/>" \
            "<tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # hope for failure
      assert_response :forbidden,
                      "way upload did not return forbidden status"

      ## Now use a public user
      auth_header = basic_authorization_header user.email, "test"

      # use the first user's open changeset
      changeset_id = changeset.id

      # create a way with pre-existing nodes
      xml = "<osm><way changeset='#{changeset_id}'>" \
            "<nd ref='#{node1.id}'/><nd ref='#{node2.id}'/>" \
            "<tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # hope for success
      assert_response :success,
                      "way upload did not return success status"
      # read id of created way and search for it
      wayid = @response.body
      checkway = Way.find(wayid)
      assert_not_nil checkway,
                     "uploaded way not found in data base after upload"
      # compare values
      assert_equal(2, checkway.nds.length, "saved way does not contain exactly one node")
      assert_equal checkway.nds[0], node1.id,
                   "saved way does not contain the right node on pos 0"
      assert_equal checkway.nds[1], node2.id,
                   "saved way does not contain the right node on pos 1"
      assert_equal checkway.changeset_id, changeset_id,
                   "saved way does not belong to the correct changeset"
      assert_equal user.id, checkway.changeset.user_id,
                   "saved way does not belong to user that created it"
      assert checkway.visible,
             "saved way is not visible"
    end

    # -------------------------------------
    # Test creating some invalid ways.
    # -------------------------------------

    def test_create_invalid
      node = create(:node)
      private_user = create(:user, :data_public => false)
      private_open_changeset = create(:changeset, :user => private_user)
      private_closed_changeset = create(:changeset, :closed, :user => private_user)
      user = create(:user)
      open_changeset = create(:changeset, :user => user)
      closed_changeset = create(:changeset, :closed, :user => user)

      ## First test with a private user to make sure that they are not authorized
      auth_header = basic_authorization_header private_user.email, "test"

      # use the first user's open changeset
      # create a way with non-existing node
      xml = "<osm><way changeset='#{private_open_changeset.id}'>" \
            "<nd ref='0'/><tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :forbidden,
                      "way upload with invalid node using a private user did not return 'forbidden'"

      # create a way with no nodes
      xml = "<osm><way changeset='#{private_open_changeset.id}'>" \
            "<tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :forbidden,
                      "way upload with no node using a private userdid not return 'forbidden'"

      # create a way inside a closed changeset
      xml = "<osm><way changeset='#{private_closed_changeset.id}'>" \
            "<nd ref='#{node.id}'/></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :forbidden,
                      "way upload to closed changeset with a private user did not return 'forbidden'"

      ## Now test with a public user
      auth_header = basic_authorization_header user.email, "test"

      # use the first user's open changeset
      # create a way with non-existing node
      xml = "<osm><way changeset='#{open_changeset.id}'>" \
            "<nd ref='0'/><tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :precondition_failed,
                      "way upload with invalid node did not return 'precondition failed'"
      assert_equal "Precondition failed: Way  requires the nodes with id in (0), which either do not exist, or are not visible.", @response.body

      # create a way with no nodes
      xml = "<osm><way changeset='#{open_changeset.id}'>" \
            "<tag k='test' v='yes' /></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :precondition_failed,
                      "way upload with no node did not return 'precondition failed'"
      assert_equal "Precondition failed: Cannot create way: data is invalid.", @response.body

      # create a way inside a closed changeset
      xml = "<osm><way changeset='#{closed_changeset.id}'>" \
            "<nd ref='#{node.id}'/></way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :conflict,
                      "way upload to closed changeset did not return 'conflict'"

      # create a way with a tag which is too long
      xml = "<osm><way changeset='#{open_changeset.id}'>" \
            "<nd ref='#{node.id}'/>" \
            "<tag k='foo' v='#{'x' * 256}'/>" \
            "</way></osm>"
      put way_create_path, :params => xml, :headers => auth_header
      # expect failure
      assert_response :bad_request,
                      "way upload to with too long tag did not return 'bad_request'"
    end

    # -------------------------------------
    # Test deleting ways.
    # -------------------------------------

    def test_delete
      private_user = create(:user, :data_public => false)
      private_open_changeset = create(:changeset, :user => private_user)
      private_closed_changeset = create(:changeset, :closed, :user => private_user)
      private_way = create(:way, :changeset => private_open_changeset)
      private_deleted_way = create(:way, :deleted, :changeset => private_open_changeset)
      private_used_way = create(:way, :changeset => private_open_changeset)
      create(:relation_member, :member => private_used_way)
      user = create(:user)
      open_changeset = create(:changeset, :user => user)
      closed_changeset = create(:changeset, :closed, :user => user)
      way = create(:way, :changeset => open_changeset)
      deleted_way = create(:way, :deleted, :changeset => open_changeset)
      used_way = create(:way, :changeset => open_changeset)
      relation_member = create(:relation_member, :member => used_way)
      relation = relation_member.relation

      # first try to delete way without auth
      delete api_way_path(way)
      assert_response :unauthorized

      # now set auth using the private user
      auth_header = basic_authorization_header private_user.email, "test"

      # this shouldn't work as with the 0.6 api we need pay load to delete
      delete api_way_path(private_way), :headers => auth_header
      assert_response :forbidden

      # Now try without having a changeset
      xml = "<osm><way id='#{private_way.id}'/></osm>"
      delete api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden

      # try to delete with an invalid (closed) changeset
      xml = update_changeset(xml_for_way(private_way), private_closed_changeset.id)
      delete api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden

      # try to delete with an invalid (non-existent) changeset
      xml = update_changeset(xml_for_way(private_way), 0)
      delete api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden

      # Now try with a valid changeset
      xml = xml_for_way(private_way)
      delete api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden

      # check the returned value - should be the new version number
      # valid delete should return the new version number, which should
      # be greater than the old version number
      # assert @response.body.to_i > current_ways(:visible_way).version,
      #   "delete request should return a new version number for way"

      # this won't work since the way is already deleted
      xml = xml_for_way(private_deleted_way)
      delete api_way_path(private_deleted_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden

      # this shouldn't work as the way is used in a relation
      xml = xml_for_way(private_used_way)
      delete api_way_path(private_used_way), :params => xml.to_s, :headers => auth_header
      assert_response :forbidden,
                      "shouldn't be able to delete a way used in a relation (#{@response.body}), when done by a private user"

      # this won't work since the way never existed
      delete api_way_path(:id => 0), :headers => auth_header
      assert_response :forbidden

      ### Now check with a public user
      # now set auth
      auth_header = basic_authorization_header user.email, "test"

      # this shouldn't work as with the 0.6 api we need pay load to delete
      delete api_way_path(way), :headers => auth_header
      assert_response :bad_request

      # Now try without having a changeset
      xml = "<osm><way id='#{way.id}'/></osm>"
      delete api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :bad_request

      # try to delete with an invalid (closed) changeset
      xml = update_changeset(xml_for_way(way), closed_changeset.id)
      delete api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict

      # try to delete with an invalid (non-existent) changeset
      xml = update_changeset(xml_for_way(way), 0)
      delete api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict

      # Now try with a valid changeset
      xml = xml_for_way(way)
      delete api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :success

      # check the returned value - should be the new version number
      # valid delete should return the new version number, which should
      # be greater than the old version number
      assert_operator @response.body.to_i, :>, way.version, "delete request should return a new version number for way"

      # this won't work since the way is already deleted
      xml = xml_for_way(deleted_way)
      delete api_way_path(deleted_way), :params => xml.to_s, :headers => auth_header
      assert_response :gone

      # this shouldn't work as the way is used in a relation
      xml = xml_for_way(used_way)
      delete api_way_path(used_way), :params => xml.to_s, :headers => auth_header
      assert_response :precondition_failed,
                      "shouldn't be able to delete a way used in a relation (#{@response.body})"
      assert_equal "Precondition failed: Way #{used_way.id} is still used by relations #{relation.id}.", @response.body

      # this won't work since the way never existed
      delete api_way_path(:id => 0), :params => xml.to_s, :headers => auth_header
      assert_response :not_found
    end

    ##
    # tests whether the API works and prevents incorrect use while trying
    # to update ways.
    def test_update
      private_user = create(:user, :data_public => false)
      private_way = create(:way, :changeset => create(:changeset, :user => private_user))
      user = create(:user)
      way = create(:way, :changeset => create(:changeset, :user => user))
      node = create(:node)
      create(:way_node, :way => private_way, :node => node)
      create(:way_node, :way => way, :node => node)

      ## First test with no user credentials
      # try and update a way without authorisation
      xml = xml_for_way(way)
      put api_way_path(way), :params => xml.to_s
      assert_response :unauthorized

      ## Second test with the private user

      # setup auth
      auth_header = basic_authorization_header private_user.email, "test"

      ## trying to break changesets

      # try and update in someone else's changeset
      xml = update_changeset(xml_for_way(private_way),
                             create(:changeset).id)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data "update with other user's changeset should be forbidden when date isn't public"

      # try and update in a closed changeset
      xml = update_changeset(xml_for_way(private_way),
                             create(:changeset, :closed, :user => private_user).id)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data "update with closed changeset should be forbidden, when data isn't public"

      # try and update in a non-existant changeset
      xml = update_changeset(xml_for_way(private_way), 0)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data("update with changeset=0 should be forbidden, when data isn't public")

      ## try and submit invalid updates
      xml = xml_replace_node(xml_for_way(private_way), node.id, 9999)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data "way with non-existent node should be forbidden, when data isn't public"

      xml = xml_replace_node(xml_for_way(private_way), node.id, create(:node, :deleted).id)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data "way with deleted node should be forbidden, when data isn't public"

      ## finally, produce a good request which will still not work
      xml = xml_for_way(private_way)
      put api_way_path(private_way), :params => xml.to_s, :headers => auth_header
      assert_require_public_data "should have failed with a forbidden when data isn't public"

      ## Finally test with the public user

      # setup auth
      auth_header = basic_authorization_header user.email, "test"

      ## trying to break changesets

      # try and update in someone else's changeset
      xml = update_changeset(xml_for_way(way),
                             create(:changeset).id)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict, "update with other user's changeset should be rejected"

      # try and update in a closed changeset
      xml = update_changeset(xml_for_way(way),
                             create(:changeset, :closed, :user => user).id)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict, "update with closed changeset should be rejected"

      # try and update in a non-existant changeset
      xml = update_changeset(xml_for_way(way), 0)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict, "update with changeset=0 should be rejected"

      ## try and submit invalid updates
      xml = xml_replace_node(xml_for_way(way), node.id, 9999)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :precondition_failed, "way with non-existent node should be rejected"

      xml = xml_replace_node(xml_for_way(way), node.id, create(:node, :deleted).id)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :precondition_failed, "way with deleted node should be rejected"

      ## next, attack the versioning
      current_way_version = way.version

      # try and submit a version behind
      xml = xml_attr_rewrite(xml_for_way(way),
                             "version", current_way_version - 1)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict, "should have failed on old version number"

      # try and submit a version ahead
      xml = xml_attr_rewrite(xml_for_way(way),
                             "version", current_way_version + 1)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict, "should have failed on skipped version number"

      # try and submit total crap in the version field
      xml = xml_attr_rewrite(xml_for_way(way),
                             "version", "p1r4t3s!")
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :conflict,
                      "should not be able to put 'p1r4at3s!' in the version field"

      ## try an update with the wrong ID
      xml = xml_for_way(create(:way))
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :bad_request,
                      "should not be able to update a way with a different ID from the XML"

      ## try an update with a minimal valid XML doc which isn't a well-formed OSM doc.
      xml = "<update/>"
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :bad_request,
                      "should not be able to update a way with non-OSM XML doc."

      ## finally, produce a good request which should work
      xml = xml_for_way(way)
      put api_way_path(way), :params => xml.to_s, :headers => auth_header
      assert_response :success, "a valid update request failed"
    end

    # ------------------------------------------------------------
    # test tags handling
    # ------------------------------------------------------------

    ##
    # Try adding a new tag to a way
    def test_add_tags
      private_user = create(:user, :data_public => false)
      private_way = create(:way_with_nodes, :nodes_count => 2, :changeset => create(:changeset, :user => private_user))
      user = create(:user)
      way = create(:way_with_nodes, :nodes_count => 2, :changeset => create(:changeset, :user => user))

      ## Try with the non-public user
      # setup auth
      auth_header = basic_authorization_header private_user.email, "test"

      # add an identical tag to the way
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = "new"
      tag_xml["v"] = "yes"

      # add the tag into the existing xml
      way_xml = xml_for_way(private_way)
      way_xml.find("//osm/way").first << tag_xml

      # try and upload it
      put api_way_path(private_way), :params => way_xml.to_s, :headers => auth_header
      assert_response :forbidden,
                      "adding a duplicate tag to a way for a non-public should fail with 'forbidden'"

      ## Now try with the public user
      # setup auth
      auth_header = basic_authorization_header user.email, "test"

      # add an identical tag to the way
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = "new"
      tag_xml["v"] = "yes"

      # add the tag into the existing xml
      way_xml = xml_for_way(way)
      way_xml.find("//osm/way").first << tag_xml

      # try and upload it
      put api_way_path(way), :params => way_xml.to_s, :headers => auth_header
      assert_response :success,
                      "adding a new tag to a way should succeed"
      assert_equal way.version + 1, @response.body.to_i
    end

    ##
    # Try adding a duplicate of an existing tag to a way
    def test_add_duplicate_tags
      private_user = create(:user, :data_public => false)
      private_way = create(:way, :changeset => create(:changeset, :user => private_user))
      private_existing_tag = create(:way_tag, :way => private_way)
      user = create(:user)
      way = create(:way, :changeset => create(:changeset, :user => user))
      existing_tag = create(:way_tag, :way => way)

      ## Try with the non-public user
      # setup auth
      auth_header = basic_authorization_header private_user.email, "test"

      # add an identical tag to the way
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = private_existing_tag.k
      tag_xml["v"] = private_existing_tag.v

      # add the tag into the existing xml
      way_xml = xml_for_way(private_way)
      way_xml.find("//osm/way").first << tag_xml

      # try and upload it
      put api_way_path(private_way), :params => way_xml.to_s, :headers => auth_header
      assert_response :forbidden,
                      "adding a duplicate tag to a way for a non-public should fail with 'forbidden'"

      ## Now try with the public user
      # setup auth
      auth_header = basic_authorization_header user.email, "test"

      # add an identical tag to the way
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = existing_tag.k
      tag_xml["v"] = existing_tag.v

      # add the tag into the existing xml
      way_xml = xml_for_way(way)
      way_xml.find("//osm/way").first << tag_xml

      # try and upload it
      put api_way_path(way), :params => way_xml.to_s, :headers => auth_header
      assert_response :bad_request,
                      "adding a duplicate tag to a way should fail with 'bad request'"
      assert_equal "Element way/#{way.id} has duplicate tags with key #{existing_tag.k}", @response.body
    end

    ##
    # Try adding a new duplicate tags to a way
    def test_new_duplicate_tags
      private_user = create(:user, :data_public => false)
      private_way = create(:way, :changeset => create(:changeset, :user => private_user))
      user = create(:user)
      way = create(:way, :changeset => create(:changeset, :user => user))

      ## First test with the non-public user so should be rejected
      # setup auth
      auth_header = basic_authorization_header private_user.email, "test"

      # create duplicate tag
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = "i_am_a_duplicate"
      tag_xml["v"] = "foobar"

      # add the tag into the existing xml
      way_xml = xml_for_way(private_way)

      # add two copies of the tag
      way_xml.find("//osm/way").first << tag_xml.copy(true) << tag_xml

      # try and upload it
      put api_way_path(private_way), :params => way_xml.to_s, :headers => auth_header
      assert_response :forbidden,
                      "adding new duplicate tags to a way using a non-public user should fail with 'forbidden'"

      ## Now test with the public user
      # setup auth
      auth_header = basic_authorization_header user.email, "test"

      # create duplicate tag
      tag_xml = XML::Node.new("tag")
      tag_xml["k"] = "i_am_a_duplicate"
      tag_xml["v"] = "foobar"

      # add the tag into the existing xml
      way_xml = xml_for_way(way)

      # add two copies of the tag
      way_xml.find("//osm/way").first << tag_xml.copy(true) << tag_xml

      # try and upload it
      put api_way_path(way), :params => way_xml.to_s, :headers => auth_header
      assert_response :bad_request,
                      "adding new duplicate tags to a way should fail with 'bad request'"
      assert_equal "Element way/#{way.id} has duplicate tags with key i_am_a_duplicate", @response.body
    end

    ##
    # Try adding a new duplicate tags to a way.
    # But be a bit subtle - use unicode decoding ambiguities to use different
    # binary strings which have the same decoding.
    def test_invalid_duplicate_tags
      private_user = create(:user, :data_public => false)
      private_changeset = create(:changeset, :user => private_user)
      user = create(:user)
      changeset = create(:changeset, :user => user)

      ## First make sure that you can't with a non-public user
      # setup auth
      auth_header = basic_authorization_header private_user.email, "test"

      # add the tag into the existing xml
      way_str = "<osm><way changeset='#{private_changeset.id}'>"
      way_str << "<tag k='addr:housenumber' v='1'/>"
      way_str << "<tag k='addr:housenumber' v='2'/>"
      way_str << "</way></osm>"

      # try and upload it
      put way_create_path, :params => way_str, :headers => auth_header
      assert_response :forbidden,
                      "adding new duplicate tags to a way with a non-public user should fail with 'forbidden'"

      ## Now do it with a public user
      # setup auth
      auth_header = basic_authorization_header user.email, "test"

      # add the tag into the existing xml
      way_str = "<osm><way changeset='#{changeset.id}'>"
      way_str << "<tag k='addr:housenumber' v='1'/>"
      way_str << "<tag k='addr:housenumber' v='2'/>"
      way_str << "</way></osm>"

      # try and upload it
      put way_create_path, :params => way_str, :headers => auth_header
      assert_response :bad_request,
                      "adding new duplicate tags to a way should fail with 'bad request'"
      assert_equal "Element way/ has duplicate tags with key addr:housenumber", @response.body
    end

    ##
    # test that a call to ways_for_node returns all ways that contain the node
    # and none that don't.
    def test_ways_for_node
      node = create(:node)
      way1 = create(:way)
      way2 = create(:way)
      create(:way_node, :way => way1, :node => node)
      create(:way_node, :way => way2, :node => node)
      # create an unrelated way
      create(:way_with_nodes, :nodes_count => 2)
      # create a way which used to use the node
      way3_v1 = create(:old_way, :version => 1)
      _way3_v2 = create(:old_way, :current_way => way3_v1.current_way, :version => 2)
      create(:old_way_node, :old_way => way3_v1, :node => node)

      get node_ways_path(node)
      assert_response :success
      ways_xml = XML::Parser.string(@response.body).parse
      assert_not_nil ways_xml, "failed to parse ways_for_node response"

      # check that the set of IDs match expectations
      expected_way_ids = [way1.id,
                          way2.id]
      found_way_ids = ways_xml.find("//osm/way").collect { |w| w["id"].to_i }
      assert_equal expected_way_ids.sort, found_way_ids.sort,
                   "expected ways for node #{node.id} did not match found"

      # check the full ways to ensure we're not missing anything
      expected_way_ids.each do |id|
        way_xml = ways_xml.find("//osm/way[@id='#{id}']").first
        assert_ways_are_equal(Way.find(id),
                              Way.from_xml_node(way_xml))
      end
    end

    private

    ##
    # update the changeset_id of a way element
    def update_changeset(xml, changeset_id)
      xml_attr_rewrite(xml, "changeset", changeset_id)
    end

    ##
    # update an attribute in the way element
    def xml_attr_rewrite(xml, name, value)
      xml.find("//osm/way").first[name] = value.to_s
      xml
    end

    ##
    # replace a node in a way element
    def xml_replace_node(xml, old_node, new_node)
      xml.find("//osm/way/nd[@ref='#{old_node}']").first["ref"] = new_node.to_s
      xml
    end
  end
end
