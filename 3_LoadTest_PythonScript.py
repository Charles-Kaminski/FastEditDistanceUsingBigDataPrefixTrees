import requests
import json
from time import sleep

base_url  = 'http://[ROXIE_IP_ADDRESS]:8131/WsEcl/submit/query/second_roxie_one_way_1_dev/cfk_ecl_example.bwr_prefix_tree_q_v1/json?maxdistancelessthan=%s&queryword=%s'

user = '[YOUR_USER_ID]'
pw   = '[YOUR_PASSWORD]'
d = 'C:\\Users\\user\\Documents\\Source\\RoxieLoadTest\\'
edit_distance = '2'

j_head = 'cfk_ecl_example.bwr_prefix_tree_q_v1Response'

if __name__ == '__main__':
    lnames = open(d + 'lnames.txt').readlines()
    lnames = [x.strip() for x in lnames]
    results = open(d + 'results.%s.txt' % edit_distance,'a')
    i = 0
    for lname in lnames:
        i = i + 1
        print i
        url = base_url % (edit_distance, lname)
        resp = requests.post(url, auth=(user, pw))
        
        j = json.loads(resp.content)
        j = j[j_head]['Results']
        s_time = j['Start_Time']['Row'][0]['Start_Time']
        result = j['Results']['Row'][0]['Results']
        e_time = j['End_Time']['Row'][0]['End_Time']
        elapsed_time = int(e_time) - int(s_time)
        out = '%s,%s,%s\n' % (lname, int(result), elapsed_time)
        results.write(out)
        results.flush()
        sleep(0.1)
        
    print 'Done.'
    
